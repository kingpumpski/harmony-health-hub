-- Next-generation appointment concurrency and state-transition hardening.
-- Reuses the existing appointment workflow RPCs and canonical clinical audit.
-- No parallel appointment subsystem is introduced.

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
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;
  IF _scheduled_at IS NULL THEN RAISE EXCEPTION 'Appointment time is required'; END IF;
  IF NULLIF(btrim(_department), '') IS NULL THEN RAISE EXCEPTION 'Department is required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(),'front_desk'::public.app_role)
  ) THEN RAISE EXCEPTION 'You are not authorized to create appointments'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id AND status <> 'merged') THEN
    RAISE EXCEPTION 'Patient does not exist or has been merged';
  END IF;

  -- Serialize competing requests for the same patient/time slot so two concurrent
  -- appointment creations cannot both pass the duplicate check.
  PERFORM pg_advisory_xact_lock(hashtextextended(_patient_id::TEXT || '|' || _scheduled_at::TEXT, 0));

  IF EXISTS (
    SELECT 1 FROM public.appointments
    WHERE patient_id = _patient_id
      AND scheduled_at = _scheduled_at
      AND COALESCE(treatment_status,'scheduled') NOT IN ('cancelled','no_show','completed')
  ) THEN
    RAISE EXCEPTION 'An active appointment already exists for this patient and time';
  END IF;

  INSERT INTO public.appointments(
    patient_id, practitioner_id, department, scheduled_at, duration_minutes,
    reason, status, treatment_status, created_at, updated_at
  ) VALUES (
    _patient_id,
    CASE WHEN public.has_role(auth.uid(),'practitioner'::public.app_role) THEN auth.uid() ELSE NULL END,
    NULLIF(btrim(_department), ''),
    _scheduled_at,
    30,
    NULLIF(btrim(_reason), ''),
    'scheduled',
    'scheduled',
    now(),
    now()
  ) RETURNING * INTO result;

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
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)
  ) THEN RAISE EXCEPTION 'Only attending clinical officers may claim appointments'; END IF;

  UPDATE public.appointments
  SET attending_officer_id = auth.uid(),
      claimed_at = COALESCE(claimed_at, now()),
      treatment_status = CASE WHEN treatment_status = 'scheduled' THEN 'claimed' ELSE treatment_status END,
      updated_at = now()
  WHERE id = _appointment_id
    AND (attending_officer_id IS NULL OR attending_officer_id = auth.uid())
    AND COALESCE(treatment_status, 'scheduled') NOT IN ('completed','cancelled','no_show')
  RETURNING * INTO result;

  IF result.id IS NULL THEN
    RAISE EXCEPTION 'Appointment is already assigned, closed, or does not exist';
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
  current_appointment public.appointments;
  result public.appointments;
  is_admin BOOLEAN;
  is_front_desk BOOLEAN;
  is_clinician BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _appointment_id IS NULL OR _scheduled_at IS NULL THEN RAISE EXCEPTION 'Appointment and time are required'; END IF;
  IF NULLIF(btrim(_department), '') IS NULL THEN RAISE EXCEPTION 'Department is required'; END IF;
  IF _treatment_status NOT IN ('scheduled','claimed','in_progress','completed','cancelled','no_show') THEN
    RAISE EXCEPTION 'Invalid treatment status';
  END IF;

  is_admin := public.has_role(auth.uid(),'admin'::public.app_role);
  is_front_desk := public.has_role(auth.uid(),'front_desk'::public.app_role);
  is_clinician := public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role);

  SELECT * INTO current_appointment
  FROM public.appointments
  WHERE id = _appointment_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found'; END IF;

  IF COALESCE(current_appointment.treatment_status,'scheduled') IN ('completed','cancelled','no_show')
     AND NOT is_admin THEN
    RAISE EXCEPTION 'Closed appointments cannot be modified';
  END IF;

  IF is_front_desk AND NOT is_admin THEN
    IF _treatment_status NOT IN ('scheduled','cancelled','no_show') THEN
      RAISE EXCEPTION 'Front desk cannot perform clinical treatment-state transitions';
    END IF;
    IF current_appointment.treatment_status = 'in_progress' THEN
      RAISE EXCEPTION 'An in-progress clinical encounter cannot be changed by front desk';
    END IF;
  ELSIF is_clinician AND NOT is_admin THEN
    IF current_appointment.attending_officer_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Appointment must be claimed by this clinical officer';
    END IF;
  ELSIF NOT is_admin THEN
    RAISE EXCEPTION 'You are not authorized to edit appointments';
  END IF;

  -- Clinical lifecycle is monotonic except for operational cancellation/no-show.
  IF NOT is_admin THEN
    IF current_appointment.treatment_status = 'scheduled' AND _treatment_status NOT IN ('scheduled','claimed','cancelled','no_show') THEN
      RAISE EXCEPTION 'Appointment must be claimed before clinical treatment begins';
    END IF;
    IF current_appointment.treatment_status = 'claimed' AND _treatment_status NOT IN ('claimed','in_progress','cancelled','no_show') THEN
      RAISE EXCEPTION 'Claimed appointments may only start, cancel, or become no-show';
    END IF;
    IF current_appointment.treatment_status = 'in_progress' AND _treatment_status NOT IN ('in_progress','completed') THEN
      RAISE EXCEPTION 'In-progress appointments may only continue or complete';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.appointments
    WHERE patient_id = current_appointment.patient_id
      AND scheduled_at = _scheduled_at
      AND id <> _appointment_id
      AND COALESCE(treatment_status,'scheduled') NOT IN ('cancelled','no_show','completed')
  ) THEN
    RAISE EXCEPTION 'An active appointment already exists for this patient and time';
  END IF;

  UPDATE public.appointments
  SET scheduled_at = _scheduled_at,
      department = NULLIF(btrim(_department),''),
      reason = NULLIF(btrim(_reason),''),
      treatment_status = _treatment_status,
      treatment_notes = CASE
        WHEN is_clinician OR is_admin THEN NULLIF(btrim(_treatment_notes),'')
        ELSE treatment_notes
      END,
      started_at = CASE WHEN _treatment_status = 'in_progress' THEN COALESCE(started_at,now()) ELSE started_at END,
      completed_at = CASE WHEN _treatment_status = 'completed' THEN COALESCE(completed_at,now()) ELSE completed_at END,
      status = CASE
        WHEN _treatment_status = 'cancelled' THEN 'cancelled'
        WHEN _treatment_status = 'completed' THEN 'completed'
        WHEN _treatment_status = 'no_show' THEN 'no_show'
        ELSE status
      END,
      updated_at = now()
  WHERE id = _appointment_id
  RETURNING * INTO result;

  RETURN result;
END;
$$;

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
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)
  ) THEN RAISE EXCEPTION 'Only clinical officers may start encounters'; END IF;

  SELECT * INTO appt FROM public.appointments WHERE id = _appointment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found'; END IF;
  IF appt.attending_officer_id IS DISTINCT FROM auth.uid()
     AND NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Claim the appointment before starting the encounter';
  END IF;
  IF COALESCE(appt.treatment_status,'scheduled') IN ('completed','cancelled','no_show') THEN
    RAISE EXCEPTION 'Closed appointments cannot start a new encounter';
  END IF;
  IF COALESCE(appt.treatment_status,'scheduled') = 'scheduled'
     AND NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Appointment must be claimed before starting the encounter';
  END IF;

  SELECT id INTO encounter_id
  FROM public.encounters
  WHERE appointment_id = _appointment_id
  ORDER BY created_at DESC
  LIMIT 1;

  IF encounter_id IS NULL THEN
    INSERT INTO public.encounters(
      patient_id, appointment_id, practitioner_id, encounter_type,
      symptoms, clerking_notes, status
    ) VALUES (
      appt.patient_id, _appointment_id, auth.uid(), 'consultation',
      NULLIF(btrim(_symptoms),''), NULLIF(btrim(_clerking_notes),''), 'draft'
    ) RETURNING id INTO encounter_id;
  END IF;

  UPDATE public.appointments
  SET treatment_status = 'in_progress',
      started_at = COALESCE(started_at,now()),
      updated_at = now()
  WHERE id = _appointment_id;

  RETURN encounter_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_appointment(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_appointment_encounter(UUID,TEXT,TEXT) TO authenticated;

COMMENT ON FUNCTION public.claim_appointment(UUID) IS 'Concurrency-safe appointment claim: one officer may own an open appointment; closed appointments cannot be claimed.';
COMMENT ON FUNCTION public.update_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,TEXT) IS 'Server-authoritative appointment state machine with role-scoped transitions and row locking.';
COMMENT ON FUNCTION public.start_appointment_encounter(UUID,TEXT,TEXT) IS 'Starts an encounter only for the assigned clinical officer (or admin), with row locking and closed-state protection.';
