-- Operational workflow security and audit hardening.
-- Additive/idempotent: tighten the appointment -> encounter boundary without
-- introducing a competing workflow or changing the existing client contract.

-- SECURITY DEFINER functions in public must not remain executable by PUBLIC.
REVOKE ALL ON FUNCTION public.create_appointment_workflow(UUID, TIMESTAMPTZ, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_appointment(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_appointment_workflow(UUID, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.start_appointment_encounter(UUID, TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(UUID, TIMESTAMPTZ, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_appointment(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment_workflow(UUID, TIMESTAMPTZ, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_appointment_encounter(UUID, TEXT, TEXT) TO authenticated;

-- Preserve the existing encounter contract while preventing concurrent starts
-- from racing over the same appointment/encounter.
CREATE OR REPLACE FUNCTION public.start_appointment_encounter(
  _appointment_id UUID,
  _symptoms TEXT DEFAULT NULL,
  _clerking_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  appt public.appointments;
  encounter_id UUID;
  encounter_status TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Only clinical officers may start encounters';
  END IF;

  SELECT * INTO appt
  FROM public.appointments
  WHERE id = _appointment_id
  FOR UPDATE;

  IF appt.id IS NULL THEN
    RAISE EXCEPTION 'Appointment not found';
  END IF;

  IF appt.attending_officer_id IS DISTINCT FROM auth.uid()
     AND NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Claim the appointment before starting the encounter';
  END IF;

  IF COALESCE(appt.treatment_status, 'scheduled') IN ('completed', 'cancelled', 'no_show') THEN
    RAISE EXCEPTION 'Closed appointments cannot start a new encounter';
  END IF;

  SELECT e.id, e.status
    INTO encounter_id, encounter_status
  FROM public.encounters e
  WHERE e.appointment_id = _appointment_id
  ORDER BY e.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF encounter_id IS NOT NULL AND encounter_status = 'completed' THEN
    RAISE EXCEPTION 'The appointment already has a completed encounter';
  END IF;

  IF encounter_id IS NULL THEN
    INSERT INTO public.encounters (
      patient_id,
      appointment_id,
      practitioner_id,
      encounter_type,
      symptoms,
      clerking_notes,
      status
    )
    VALUES (
      appt.patient_id,
      _appointment_id,
      auth.uid(),
      'consultation',
      NULLIF(trim(_symptoms), ''),
      NULLIF(trim(_clerking_notes), ''),
      'draft'
    )
    RETURNING id INTO encounter_id;
  END IF;

  UPDATE public.appointments
  SET treatment_status = 'in_progress',
      started_at = COALESCE(started_at, now()),
      updated_at = now()
  WHERE id = _appointment_id;

  RETURN encounter_id;
END;
$$;

REVOKE ALL ON FUNCTION public.start_appointment_encounter(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_appointment_encounter(UUID, TEXT, TEXT) TO authenticated;

-- Appointment lifecycle changes are high-value operational events and should
-- use the existing system audit infrastructure rather than a second audit log.
DO $$
BEGIN
  IF to_regprocedure('public.audit_clinical_record_change()') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_audit_appointments_changes ON public.appointments;
    CREATE TRIGGER trg_audit_appointments_changes
      AFTER INSERT OR UPDATE OR DELETE ON public.appointments
      FOR EACH ROW
      EXECUTE FUNCTION public.audit_clinical_record_change();
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
