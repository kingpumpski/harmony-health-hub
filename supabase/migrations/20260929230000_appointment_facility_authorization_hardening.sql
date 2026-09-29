-- Authorization hardening: bind appointment mutations and worklist reads to the
-- active facility patient-tenancy boundary introduced by the patient access foundation.
-- This migration is intentionally additive and must be validated in an isolated
-- environment before production application.
-- Patient/appointment row locks make the authorization decision and subsequent
-- mutation share the same transaction snapshot, reducing TOCTOU exposure when
-- facility links or appointment ownership are changed concurrently.

CREATE OR REPLACE FUNCTION public.create_appointment_workflow(
  _patient_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _department TEXT,
  _reason TEXT DEFAULT NULL
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  result public.appointments;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role((SELECT auth.uid()), 'admin'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'practitioner'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'nurse'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'midwife'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'specialist_nurse'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'front_desk'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Not authorized to schedule appointments';
  END IF;

  IF NOT public.hms_patient_has_facility_access(_patient_id) THEN
    RAISE EXCEPTION 'Patient facility access denied';
  END IF;

  PERFORM 1
  FROM public.patients
  WHERE id = _patient_id
    AND COALESCE(status, 'active') <> 'inactive'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active patient does not exist';
  END IF;

  IF _scheduled_at IS NULL THEN
    RAISE EXCEPTION 'Scheduled time is required';
  END IF;

  INSERT INTO public.appointments(
    patient_id, practitioner_id, department, scheduled_at, duration_minutes,
    reason, status, notes, created_at, updated_at, treatment_status, consultation_type
  )
  VALUES(
    _patient_id,
    CASE
      WHEN public.has_role((SELECT auth.uid()), 'practitioner'::public.app_role)
      THEN (SELECT auth.uid())
      ELSE NULL
    END,
    NULLIF(pg_catalog.trim(_department), ''),
    _scheduled_at,
    30,
    NULLIF(pg_catalog.trim(_reason), ''),
    'scheduled',
    NULL,
    pg_catalog.now(),
    pg_catalog.now(),
    'scheduled',
    'General Consultation'
  )
  RETURNING * INTO result;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_appointment_workflow(
  _patient_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _department TEXT,
  _reason TEXT,
  _consultation_type TEXT,
  _practitioner_id UUID DEFAULT NULL
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  result public.appointments;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role((SELECT auth.uid()), 'admin'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'practitioner'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'nurse'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'midwife'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'specialist_nurse'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'front_desk'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Not authorized to schedule appointments';
  END IF;

  IF NOT public.hms_patient_has_facility_access(_patient_id) THEN
    RAISE EXCEPTION 'Patient facility access denied';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.patients
    WHERE id = _patient_id
      AND COALESCE(status, 'active') <> 'inactive'
  ) THEN
    RAISE EXCEPTION 'Active patient does not exist';
  END IF;

  IF _scheduled_at IS NULL THEN
    RAISE EXCEPTION 'Scheduled time is required';
  END IF;

  IF pg_catalog.nullif(pg_catalog.trim(_consultation_type), '') IS NULL THEN
    RAISE EXCEPTION 'Consultation type is required';
  END IF;

  IF _practitioner_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.profiles p WHERE p.id = _practitioner_id
     )
  THEN
    RAISE EXCEPTION 'Selected clinician does not exist';
  END IF;

  INSERT INTO public.appointments(
    patient_id, practitioner_id, department, scheduled_at, duration_minutes,
    reason, status, notes, created_at, updated_at, treatment_status, consultation_type
  )
  VALUES(
    _patient_id,
    _practitioner_id,
    NULLIF(pg_catalog.trim(_department), ''),
    _scheduled_at,
    30,
    NULLIF(pg_catalog.trim(_reason), ''),
    'scheduled',
    NULL,
    pg_catalog.now(),
    pg_catalog.now(),
    'scheduled',
    pg_catalog.nullif(pg_catalog.trim(_consultation_type), '')
  )
  RETURNING * INTO result;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_appointment_workflow(
  _appointment_id UUID,
  _scheduled_at TIMESTAMPTZ,
  _department TEXT,
  _reason TEXT,
  _treatment_status TEXT,
  _treatment_notes TEXT DEFAULT NULL,
  _consultation_type TEXT DEFAULT NULL,
  _practitioner_id UUID DEFAULT NULL
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  result public.appointments;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF _treatment_status NOT IN ('scheduled','claimed','in_progress','completed','cancelled','no_show') THEN
    RAISE EXCEPTION 'Invalid treatment status';
  END IF;

  IF NOT (
    public.has_role((SELECT auth.uid()), 'admin'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'practitioner'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'nurse'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'midwife'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'specialist_nurse'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'front_desk'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'You are not authorized to edit appointments';
  END IF;

  PERFORM 1
  FROM public.appointments a
  WHERE a.id = _appointment_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Appointment not found';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.appointments a
    WHERE a.id = _appointment_id
      AND public.hms_patient_has_facility_access(a.patient_id)
  ) THEN
    RAISE EXCEPTION 'Appointment facility access denied';
  END IF;

  UPDATE public.appointments
  SET scheduled_at = _scheduled_at,
      department = NULLIF(pg_catalog.trim(_department), ''),
      reason = NULLIF(pg_catalog.trim(_reason), ''),
      treatment_status = _treatment_status,
      treatment_notes = NULLIF(pg_catalog.trim(_treatment_notes), ''),
      consultation_type = COALESCE(
        NULLIF(pg_catalog.trim(_consultation_type), ''),
        consultation_type
      ),
      practitioner_id = CASE
        WHEN _practitioner_id IS NULL THEN practitioner_id
        ELSE _practitioner_id
      END,
      started_at = CASE
        WHEN _treatment_status = 'in_progress' THEN COALESCE(started_at, pg_catalog.now())
        ELSE started_at
      END,
      completed_at = CASE
        WHEN _treatment_status = 'completed' THEN COALESCE(completed_at, pg_catalog.now())
        ELSE completed_at
      END,
      status = CASE
        WHEN _treatment_status = 'cancelled' THEN 'cancelled'
        WHEN _treatment_status = 'completed' THEN 'completed'
        ELSE status
      END,
      updated_at = pg_catalog.now()
  WHERE id = _appointment_id
    AND (
      attending_officer_id = (SELECT auth.uid())
      OR public.has_role((SELECT auth.uid()), 'admin'::public.app_role)
      OR public.has_role((SELECT auth.uid()), 'front_desk'::public.app_role)
    )
  RETURNING * INTO result;

  IF result.id IS NULL THEN
    RAISE EXCEPTION 'Appointment not found or not assigned to this officer';
  END IF;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_appointment_worklist(_limit INTEGER DEFAULT 300)
RETURNS TABLE(
  id UUID,
  patient_id UUID,
  patient_code TEXT,
  patient_first_name TEXT,
  patient_last_name TEXT,
  scheduled_at TIMESTAMPTZ,
  consultation_type TEXT,
  practitioner_id UUID,
  practitioner_name TEXT,
  department TEXT,
  reason TEXT,
  status TEXT,
  attending_officer_id UUID,
  treatment_status TEXT,
  treatment_notes TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_limit INTEGER := pg_catalog.greatest(1, pg_catalog.least(pg_catalog.coalesce(_limit, 300), 500));
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role((SELECT auth.uid()), 'admin'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'practitioner'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'nurse'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'midwife'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'specialist_nurse'::public.app_role)
    OR public.has_role((SELECT auth.uid()), 'front_desk'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Appointment worklist access denied';
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    a.patient_id,
    p.patient_code,
    p.first_name,
    p.last_name,
    a.scheduled_at,
    pg_catalog.coalesce(a.consultation_type, 'General Consultation'),
    a.practitioner_id,
    pg_catalog.nullif(pg_catalog.trim(pg_catalog.concat_ws(' ', pr.first_name, pr.last_name)), ''),
    a.department,
    a.reason,
    a.status,
    a.attending_officer_id,
    a.treatment_status,
    a.treatment_notes
  FROM public.appointments a
  JOIN public.patients p ON p.id = a.patient_id
  LEFT JOIN public.profiles pr ON pr.id = a.practitioner_id
  WHERE pg_catalog.coalesce(p.status, 'active') <> 'inactive'
    AND public.hms_patient_has_facility_access(a.patient_id)
  ORDER BY a.scheduled_at ASC
  LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.create_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,TEXT,TEXT,UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_appointment_worklist(INTEGER) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment_workflow(UUID,TIMESTAMPTZ,TEXT,TEXT,TEXT,TEXT,TEXT,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_appointment_worklist(INTEGER) TO authenticated;

NOTIFY pgrst, 'reload schema';
