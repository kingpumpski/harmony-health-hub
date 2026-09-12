-- Phase 8: prevent client-side fabrication or premature review of AI results.
-- Provider/backend completion must use the SECURITY DEFINER RPC below.

CREATE OR REPLACE FUNCTION public.complete_ai_clinical_session(
  _session_id UUID,
  _output_snapshot JSONB,
  _model_provider TEXT,
  _model_name TEXT,
  _provenance JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _updated_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF _output_snapshot IS NULL OR _output_snapshot = '{}'::jsonb THEN
    RAISE EXCEPTION 'AI output is required';
  END IF;
  IF NULLIF(trim(_model_provider), '') IS NULL OR NULLIF(trim(_model_name), '') IS NULL THEN
    RAISE EXCEPTION 'AI model provenance is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.ai_clinical_sessions
    WHERE id = _session_id
      AND status = 'analysis_requested'
      AND (
        created_by = auth.uid()
        OR public.has_role(auth.uid(), 'admin'::public.app_role)
        OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
        OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
        OR public.has_role(auth.uid(), 'nurse'::public.app_role)
        OR public.has_role(auth.uid(), 'midwife'::public.app_role)
        OR public.has_role(auth.uid(), 'pharmacist'::public.app_role)
      )
  ) THEN
    RAISE EXCEPTION 'AI clinical session is not eligible for completion';
  END IF;

  UPDATE public.ai_clinical_sessions
  SET output_snapshot = _output_snapshot,
      model_provider = trim(_model_provider),
      model_name = trim(_model_name),
      provenance = COALESCE(_provenance, '{}'::jsonb),
      status = 'completed',
      review_status = 'not_reviewed',
      reviewed_by = NULL,
      reviewed_at = NULL,
      updated_at = now()
  WHERE id = _session_id
  RETURNING id INTO _updated_id;

  PERFORM public.record_ai_clinical_event(
    _session_id,
    'analysis_completed',
    jsonb_build_object(
      'model_provider', trim(_model_provider),
      'model_name', trim(_model_name)
    )
  );

  RETURN _updated_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.complete_ai_clinical_session(UUID, JSONB, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_ai_clinical_session(UUID, JSONB, TEXT, TEXT, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_ai_clinical_session_state()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status IN ('completed', 'reviewed', 'rejected') THEN
    IF NEW.output_snapshot IS NULL
       OR NEW.model_provider IS NULL
       OR NEW.model_name IS NULL THEN
      RAISE EXCEPTION 'Completed AI sessions require output and model provenance';
    END IF;
  END IF;

  IF NEW.review_status <> 'not_reviewed' AND NEW.status NOT IN ('completed', 'reviewed', 'rejected') THEN
    RAISE EXCEPTION 'AI sessions may only be reviewed after analysis is completed';
  END IF;

  IF NEW.review_status <> 'not_reviewed' AND NEW.reviewed_by IS NULL THEN
    RAISE EXCEPTION 'Reviewed AI sessions require a reviewer';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS t_validate_ai_clinical_session_state ON public.ai_clinical_sessions;
CREATE TRIGGER t_validate_ai_clinical_session_state
  BEFORE INSERT OR UPDATE ON public.ai_clinical_sessions
  FOR EACH ROW EXECUTE FUNCTION public.validate_ai_clinical_session_state();

-- The earlier generic owner-update policy is intentionally retained for draft/request state,
-- but clients must not be able to manufacture completed model output. The completion RPC is
-- the supported path for provider output persistence.
DROP POLICY IF EXISTS "AI session owners update drafts" ON public.ai_clinical_sessions;
CREATE POLICY "AI session owners update request state"
  ON public.ai_clinical_sessions FOR UPDATE TO authenticated
  USING (
    (created_by = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role))
    AND status IN ('draft', 'analysis_requested')
  )
  WITH CHECK (
    (created_by = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role))
    AND status IN ('draft', 'analysis_requested')
    AND review_status = 'not_reviewed'
    AND reviewed_by IS NULL
  );

COMMENT ON FUNCTION public.complete_ai_clinical_session(UUID, JSONB, TEXT, TEXT, JSONB) IS
  'Persist provider-generated clinical AI output with model provenance and append an analysis_completed event.';
