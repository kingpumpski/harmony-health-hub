-- Keep the new treatment workflow independent from legacy appointment status constraints.
-- The treatment_status column carries no-show explicitly; the legacy status remains scheduled/completed/cancelled.

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
  ) THEN RAISE EXCEPTION 'You are not authorized to edit appointments'; END IF;
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

  IF result.id IS NULL THEN RAISE EXCEPTION 'Appointment not found or not assigned to this officer'; END IF;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_appointment_workflow(UUID, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) TO authenticated;
