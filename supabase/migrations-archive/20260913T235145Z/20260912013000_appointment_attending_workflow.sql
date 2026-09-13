-- Appointment workflow: allow authorized officers to claim, edit and progress scheduled care.
-- Existing appointment data is preserved; new workflow columns are additive.

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS attending_officer_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS treatment_status TEXT NOT NULL DEFAULT 'scheduled',
  ADD COLUMN IF NOT EXISTS treatment_notes TEXT,
  ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_appointments_attending_officer
  ON public.appointments(attending_officer_id, scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_appointments_treatment_status
  ON public.appointments(treatment_status, scheduled_at DESC);
CREATE INDEX IF NOT EXISTS idx_appointments_patient_schedule
  ON public.appointments(patient_id, scheduled_at DESC);

ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Clinical staff manage appointments" ON public.appointments;
CREATE POLICY "Clinical staff manage appointments"
  ON public.appointments FOR ALL TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'front_desk'::public.app_role)
  )
  WITH CHECK (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'front_desk'::public.app_role)
  );

CREATE OR REPLACE FUNCTION public.claim_appointment(_appointment_id UUID)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.appointments;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Only attending clinical officers may claim appointments';
  END IF;

  UPDATE public.appointments
  SET attending_officer_id = auth.uid(),
      claimed_at = COALESCE(claimed_at, now()),
      treatment_status = CASE WHEN treatment_status = 'scheduled' THEN 'claimed' ELSE treatment_status END,
      updated_at = COALESCE(updated_at, now())
  WHERE id = _appointment_id
    AND (attending_officer_id IS NULL OR attending_officer_id = auth.uid())
  RETURNING * INTO result;

  IF result.id IS NULL THEN
    RAISE EXCEPTION 'Appointment is already assigned to another officer or does not exist';
  END IF;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_appointment_workflow(
  _appointment_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _department TEXT,
  _reason TEXT,
  _treatment_status TEXT,
  _treatment_notes TEXT DEFAULT NULL
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.appointments;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'front_desk'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'You are not authorized to edit appointments';
  END IF;
  IF _treatment_status NOT IN ('scheduled','claimed','in_progress','completed','cancelled','no_show') THEN
    RAISE EXCEPTION 'Invalid treatment status';
  END IF;

  UPDATE public.appointments
  SET scheduled_at = _scheduled_at,
      department = NULLIF(trim(_department), ''),
      reason = NULLIF(trim(_reason), ''),
      treatment_status = _treatment_status,
      treatment_notes = NULLIF(trim(_treatment_notes), ''),
      started_at = CASE WHEN _treatment_status = 'in_progress' THEN COALESCE(started_at, now()) ELSE started_at END,
      completed_at = CASE WHEN _treatment_status = 'completed' THEN COALESCE(completed_at, now()) ELSE completed_at END,
      status = CASE
        WHEN _treatment_status = 'cancelled' THEN 'cancelled'
        WHEN _treatment_status = 'completed' THEN 'completed'
        WHEN _treatment_status = 'no_show' THEN 'no_show'
        ELSE status
      END,
      updated_at = COALESCE(updated_at, now())
  WHERE id = _appointment_id
    AND (
      attending_officer_id = auth.uid()
      OR public.has_role(auth.uid(), 'admin'::public.app_role)
      OR public.has_role(auth.uid(), 'front_desk'::public.app_role)
    )
  RETURNING * INTO result;

  IF result.id IS NULL THEN
    RAISE EXCEPTION 'Appointment not found or not assigned to this officer';
  END IF;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.claim_appointment(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment_workflow(UUID, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON COLUMN public.appointments.attending_officer_id IS 'Clinician/officer currently responsible for the appointment treatment workflow.';
COMMENT ON COLUMN public.appointments.treatment_status IS 'Operational care status independent of the appointment booking status.';
