-- Harden the AI clinical request transition so the status change and audit event are atomic.
-- Clients may request analysis, but cannot manufacture completion or review state.

CREATE OR REPLACE FUNCTION public.request_ai_clinical_analysis(
  _session_id UUID,
  _metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _event_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.ai_clinical_sessions
    WHERE id = _session_id
      AND created_by = auth.uid()
      AND status = 'draft'
      AND review_status = 'not_reviewed'
      AND reviewed_by IS NULL
  ) THEN
    RAISE EXCEPTION 'AI clinical session is not eligible for analysis request';
  END IF;

  UPDATE public.ai_clinical_sessions
  SET status = 'analysis_requested',
      updated_at = now()
  WHERE id = _session_id
    AND created_by = auth.uid()
    AND status = 'draft'
    AND review_status = 'not_reviewed'
    AND reviewed_by IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI clinical session request transition was not applied';
  END IF;

  _event_id := public.record_ai_clinical_event(
    _session_id,
    'analysis_requested',
    COALESCE(_metadata, '{}'::jsonb)
      || jsonb_build_object('requested_by', auth.uid())
  );

  RETURN _event_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.request_ai_clinical_analysis(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_ai_clinical_analysis(UUID, JSONB) TO authenticated;

-- A review is only valid after provider output has been persisted by the completion RPC.
CREATE OR REPLACE FUNCTION public.review_ai_clinical_session(
  _session_id UUID,
  _review_status TEXT,
  _metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _event_type TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF _review_status NOT IN ('approved', 'amended', 'rejected') THEN
    RAISE EXCEPTION 'Invalid AI review status';
  END IF;

  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'pharmacist'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Clinical reviewer role required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.ai_clinical_sessions
    WHERE id = _session_id
      AND status = 'completed'
      AND output_snapshot IS NOT NULL
      AND model_provider IS NOT NULL
      AND model_name IS NOT NULL
      AND review_status = 'not_reviewed'
  ) THEN
    RAISE EXCEPTION 'AI clinical session is not eligible for review';
  END IF;

  UPDATE public.ai_clinical_sessions
  SET review_status = _review_status,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      status = 'reviewed',
      updated_at = now()
  WHERE id = _session_id
    AND status = 'completed'
    AND review_status = 'not_reviewed';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'AI clinical review transition was not applied';
  END IF;

  _event_type := CASE _review_status
    WHEN 'approved' THEN 'review_approved'
    WHEN 'amended' THEN 'review_amended'
    ELSE 'review_rejected'
  END;

  RETURN public.record_ai_clinical_event(
    _session_id,
    _event_type,
    COALESCE(_metadata, '{}'::jsonb)
      || jsonb_build_object('reviewed_by', auth.uid(), 'review_status', _review_status)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.review_ai_clinical_session(UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_ai_clinical_session(UUID, TEXT, JSONB) TO authenticated;

COMMENT ON FUNCTION public.request_ai_clinical_analysis(UUID, JSONB) IS
  'Atomically transitions an owned draft AI clinical session to analysis_requested and records provenance.';
COMMENT ON FUNCTION public.review_ai_clinical_session(UUID, TEXT, JSONB) IS
  'Records qualified clinician review only after provider-generated AI output and provenance exist.';
