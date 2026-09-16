-- Make AI clinical session creation server-authoritative.
-- The browser may assemble a documented context snapshot, but cannot directly insert
-- an AI session or forge its creator/audit event.

CREATE OR REPLACE FUNCTION public.create_ai_clinical_session(
  _patient_id UUID,
  _specialist TEXT,
  _input_snapshot JSONB,
  _provenance JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _session_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF _patient_id IS NULL OR _specialist IS NULL OR btrim(_specialist) = '' THEN
    RAISE EXCEPTION 'Patient and specialist are required';
  END IF;

  IF _input_snapshot IS NULL OR jsonb_typeof(_input_snapshot) <> 'object' THEN
    RAISE EXCEPTION 'AI input snapshot must be a JSON object';
  END IF;

  IF _provenance IS NULL OR jsonb_typeof(_provenance) <> 'object' THEN
    RAISE EXCEPTION 'AI provenance must be a JSON object';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient record not found';
  END IF;

  INSERT INTO public.ai_clinical_sessions (
    patient_id,
    specialist,
    status,
    review_status,
    input_snapshot,
    provenance,
    created_by
  ) VALUES (
    _patient_id,
    btrim(_specialist),
    'draft',
    'not_reviewed',
    _input_snapshot,
    COALESCE(_provenance, '{}'::jsonb)
      || jsonb_build_object('created_by', auth.uid(), 'created_at', now()),
    auth.uid()
  )
  RETURNING id INTO _session_id;

  PERFORM public.record_ai_clinical_event(
    _session_id,
    'session_created',
    COALESCE(_provenance, '{}'::jsonb)
      || jsonb_build_object('created_by', auth.uid())
  );

  RETURN _session_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_ai_clinical_session(UUID, TEXT, JSONB, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ai_clinical_session(UUID, TEXT, JSONB, JSONB) TO authenticated;

COMMENT ON FUNCTION public.create_ai_clinical_session(UUID, TEXT, JSONB, JSONB) IS
  'Creates an AI clinical draft atomically with server-authoritative creator attribution and provenance audit.';

-- Prevent clients from bypassing the workflow through direct table writes.
REVOKE INSERT, UPDATE, DELETE ON public.ai_clinical_sessions FROM authenticated;
