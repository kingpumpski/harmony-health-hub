-- Operational RPC contract reconciliation.
-- This migration is intentionally idempotent and repairs environments where
-- earlier appointment workflow migrations were not fully exposed through
-- PostgREST/schema cache. It also establishes the appointment creation path
-- used by the current UI.

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS attending_officer_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS claimed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS treatment_status TEXT NOT NULL DEFAULT 'scheduled',
  ADD COLUMN IF NOT EXISTS treatment_notes TEXT,
  ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_appointments_operational_queue
  ON public.appointments(scheduled_at DESC, treatment_status, attending_officer_id);

CREATE OR REPLACE FUNCTION public.create_appointment_workflow(
  _patient_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _department TEXT,
  _reason TEXT DEFAULT NULL
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.appointments;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient does not exist';
  END IF;

  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'front_desk'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'You are not authorized to create appointments';
  END IF;

  IF _scheduled_at IS NULL THEN
    RAISE EXCEPTION 'Appointment time is required';
  END IF;

  INSERT INTO public.appointments (
    patient_id,
    scheduled_at,
    department,
    reason,
    status,
    treatment_status,
    created_by
  )
  VALUES (
    _patient_id,
    _scheduled_at,
    NULLIF(trim(_department), ''),
    NULLIF(trim(_reason), ''),
    'scheduled',
    'scheduled',
    auth.uid()
  )
  RETURNING * INTO result;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_appointment(_appointment_id UUID)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.appointments;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

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
      treatment_status = CASE
        WHEN treatment_status IS NULL OR treatment_status = 'scheduled' THEN 'claimed'
        ELSE treatment_status
      END,
      updated_at = COALESCE(updated_at, now())
  WHERE id = _appointment_id
    AND (attending_officer_id IS NULL OR attending_officer_id = auth.uid())
    AND COALESCE(treatment_status, 'scheduled') NOT IN ('completed', 'cancelled', 'no_show')
  RETURNING * INTO result;

  IF result.id IS NULL THEN
    RAISE EXCEPTION 'Appointment is already assigned to another officer, closed, or does not exist';
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
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF _treatment_status NOT IN ('scheduled','claimed','in_progress','completed','cancelled','no_show') THEN
    RAISE EXCEPTION 'Invalid treatment status';
  END IF;

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

GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(UUID, TIMESTAMPTZ, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_appointment(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment_workflow(UUID, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- Force PostgREST to refresh its function/schema cache after migration.
NOTIFY pgrst, 'reload schema';
