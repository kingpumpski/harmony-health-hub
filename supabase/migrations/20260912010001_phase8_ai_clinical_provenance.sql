-- Phase 8: persistent clinical AI provenance and clinician-review controls.
-- AI remains decision support only. No autonomous diagnosis or treatment authority is granted.

CREATE TABLE IF NOT EXISTS public.ai_clinical_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  specialist TEXT NOT NULL CHECK (specialist IN (
    'physician',
    'surgeon',
    'neurosurgeon',
    'radiologist',
    'ophthalmologist',
    'pharmacist',
    'nurse'
  )),
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN (
    'draft',
    'analysis_requested',
    'completed',
    'reviewed',
    'rejected'
  )),
  input_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
  output_snapshot JSONB,
  model_provider TEXT,
  model_name TEXT,
  provenance JSONB NOT NULL DEFAULT '{}'::jsonb,
  review_status TEXT NOT NULL DEFAULT 'not_reviewed' CHECK (review_status IN (
    'not_reviewed',
    'approved',
    'amended',
    'rejected'
  )),
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_clinical_sessions_patient_time
  ON public.ai_clinical_sessions(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_clinical_sessions_status
  ON public.ai_clinical_sessions(status, review_status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_clinical_sessions_creator
  ON public.ai_clinical_sessions(created_by, created_at DESC);

ALTER TABLE public.ai_clinical_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Clinical staff read AI sessions" ON public.ai_clinical_sessions;
CREATE POLICY "Clinical staff read AI sessions"
  ON public.ai_clinical_sessions FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'lab_technician'::public.app_role)
    OR public.has_role(auth.uid(), 'pharmacist'::public.app_role)
    OR public.has_role(auth.uid(), 'front_desk'::public.app_role)
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
      OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
      OR public.has_role(auth.uid(), 'lab_technician'::public.app_role)
      OR public.has_role(auth.uid(), 'pharmacist'::public.app_role)
    )
  );

DROP POLICY IF EXISTS "AI session owners update drafts" ON public.ai_clinical_sessions;
CREATE POLICY "AI session owners update drafts"
  ON public.ai_clinical_sessions FOR UPDATE TO authenticated
  USING (
    created_by = auth.uid()
    OR public.has_role(auth.uid(), 'admin'::public.app_role)
  )
  WITH CHECK (
    (created_by = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role))
    AND reviewed_by IS NULL OR reviewed_by = auth.uid()
  );

CREATE OR REPLACE FUNCTION public.touch_ai_clinical_session()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();

  IF NEW.review_status <> 'not_reviewed' AND NEW.reviewed_by IS NULL THEN
    RAISE EXCEPTION 'AI review requires an authenticated reviewer';
  END IF;

  IF NEW.review_status = 'not_reviewed' THEN
    NEW.reviewed_by := NULL;
    NEW.reviewed_at := NULL;
  ELSIF NEW.reviewed_at IS NULL THEN
    NEW.reviewed_at := now();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS t_ai_clinical_session_guard ON public.ai_clinical_sessions;
CREATE TRIGGER t_ai_clinical_session_guard
  BEFORE UPDATE ON public.ai_clinical_sessions
  FOR EACH ROW EXECUTE FUNCTION public.touch_ai_clinical_session();

REVOKE DELETE ON public.ai_clinical_sessions FROM authenticated;

CREATE TABLE IF NOT EXISTS public.ai_clinical_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.ai_clinical_sessions(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL CHECK (event_type IN (
    'session_created',
    'analysis_requested',
    'analysis_completed',
    'review_approved',
    'review_amended',
    'review_rejected'
  )),
  actor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_clinical_events_session_time
  ON public.ai_clinical_events(session_id, created_at DESC);

ALTER TABLE public.ai_clinical_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Clinical staff read AI events" ON public.ai_clinical_events;
CREATE POLICY "Clinical staff read AI events"
  ON public.ai_clinical_events FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.ai_clinical_sessions s
      WHERE s.id = session_id
    )
    AND (
      public.has_role(auth.uid(), 'admin'::public.app_role)
      OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
      OR public.has_role(auth.uid(), 'nurse'::public.app_role)
      OR public.has_role(auth.uid(), 'midwife'::public.app_role)
      OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
      OR public.has_role(auth.uid(), 'lab_technician'::public.app_role)
      OR public.has_role(auth.uid(), 'pharmacist'::public.app_role)
    )
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

REVOKE INSERT, UPDATE, DELETE ON public.ai_clinical_events FROM authenticated;
GRANT EXECUTE ON FUNCTION public.record_ai_clinical_event(UUID, TEXT, JSONB) TO authenticated;

COMMENT ON TABLE public.ai_clinical_sessions IS
  'Persistent clinical AI decision-support sessions. AI output is advisory and requires clinician review.';
COMMENT ON TABLE public.ai_clinical_events IS
  'Append-only provenance events for clinical AI sessions.';
