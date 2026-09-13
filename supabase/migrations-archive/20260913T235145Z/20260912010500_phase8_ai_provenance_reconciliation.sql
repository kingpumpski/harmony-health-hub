-- Reconcile Phase 8 provenance constraints without deleting existing data.

ALTER TABLE IF EXISTS public.ai_clinical_events
  ALTER COLUMN actor_id DROP NOT NULL;

DROP POLICY IF EXISTS "AI session owners update drafts" ON public.ai_clinical_sessions;
CREATE POLICY "AI session owners update drafts"
  ON public.ai_clinical_sessions FOR UPDATE TO authenticated
  USING (
    created_by = auth.uid()
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
  WITH CHECK (
    (created_by = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role))
    AND (reviewed_by IS NULL OR reviewed_by = auth.uid())
  );

CREATE OR REPLACE FUNCTION public.record_ai_clinical_event(
  _session_id UUID,
  _event_type TEXT,
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
    SELECT 1 FROM public.ai_clinical_sessions
    WHERE id = _session_id
      AND (
        created_by = auth.uid()
        OR public.has_role(auth.uid(), 'admin'::public.app_role)
        OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
        OR public.has_role(auth.uid(), 'nurse'::public.app_role)
        OR public.has_role(auth.uid(), 'midwife'::public.app_role)
        OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
        OR public.has_role(auth.uid(), 'lab_technician'::public.app_role)
        OR public.has_role(auth.uid(), 'pharmacist'::public.app_role)
      )
  ) THEN
    RAISE EXCEPTION 'AI clinical session is not accessible to this user';
  END IF;

  IF _event_type NOT IN ('session_created','analysis_requested','analysis_completed','review_approved','review_amended','review_rejected') THEN
    RAISE EXCEPTION 'Unsupported AI clinical event type';
  END IF;

  INSERT INTO public.ai_clinical_events(session_id, event_type, actor_id, metadata)
  VALUES (_session_id, _event_type, auth.uid(), COALESCE(_metadata, '{}'::jsonb))
  RETURNING id INTO _event_id;

  RETURN _event_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_ai_clinical_event(UUID, TEXT, JSONB) TO authenticated;
