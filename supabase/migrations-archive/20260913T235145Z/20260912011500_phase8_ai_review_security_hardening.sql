-- Phase 8: tighten AI clinical access and make review transitions auditable.

DROP POLICY IF EXISTS "Clinical staff read AI sessions" ON public.ai_clinical_sessions;
CREATE POLICY "Clinical staff read AI sessions"
  ON public.ai_clinical_sessions FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'lab_technician'::public.app_role)
    OR public.has_role(auth.uid(), 'pharmacist'::public.app_role)
  );

DROP POLICY IF EXISTS "Clinical staff create AI sessions" ON public.ai_clinical_sessions;
CREATE POLICY "Clinical staff create AI sessions"
  ON public.ai_clinical_sessions FOR INSERT TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND (
      public.has_role(auth.uid(), 'admin'::public.app_role)
      OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
      OR public.has_role(auth.uid(), 'nurse'::public.app_role)
      OR public.has_role(auth.uid(), 'midwife'::public.app_role)
      OR public.has_role(auth.uid(), 'lab_technician'::public.app_role)
      OR public.has_role(auth.uid(), 'pharmacist'::public.app_role)
    )
  );

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
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'pharmacist'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Clinical reviewer role required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.ai_clinical_sessions
    WHERE id = _session_id
  ) THEN
    RAISE EXCEPTION 'AI clinical session not found';
  END IF;

  UPDATE public.ai_clinical_sessions
  SET review_status = _review_status,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      status = 'reviewed'
  WHERE id = _session_id;

  _event_type := CASE _review_status
    WHEN 'approved' THEN 'review_approved'
    WHEN 'amended' THEN 'review_amended'
    ELSE 'review_rejected'
  END;

  RETURN public.record_ai_clinical_event(
    _session_id,
    _event_type,
    COALESCE(_metadata, '{}'::jsonb) || jsonb_build_object('reviewed_by', auth.uid(), 'review_status', _review_status)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.review_ai_clinical_session(UUID, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_ai_clinical_session(UUID, TEXT, JSONB) TO authenticated;
COMMENT ON FUNCTION public.review_ai_clinical_session(UUID, TEXT, JSONB) IS
  'Records a qualified clinician review of an AI clinical decision-support session; never grants autonomous clinical authority.';
