BEGIN;

-- Clinical appointment workflows must be scoped to the active facility even for
-- administrative users. Admins can switch facility context before working in
-- another facility; cross-facility read access must not surface appointments
-- that the encounter-write trigger will reject.

CREATE OR REPLACE FUNCTION public.get_appointment_worklist(_limit integer DEFAULT 300)
RETURNS TABLE(
  id uuid, patient_id uuid, patient_code text, patient_first_name text,
  patient_last_name text, scheduled_at timestamptz, consultation_type text,
  practitioner_id uuid, practitioner_name text, department text, reason text,
  status text, attending_officer_id uuid, treatment_status text, treatment_notes text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_limit integer := greatest(1, least(coalesce(_limit, 300), 500));
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(v_user,'admin'::public.app_role)
    OR public.has_role(v_user,'it_admin'::public.app_role)
    OR public.has_role(v_user,'system_superuser'::public.app_role)
    OR public.has_role(v_user,'practitioner'::public.app_role)
    OR public.has_role(v_user,'nurse'::public.app_role)
    OR public.has_role(v_user,'midwife'::public.app_role)
    OR public.has_role(v_user,'specialist_nurse'::public.app_role)
    OR public.has_role(v_user,'front_desk'::public.app_role)
  ) THEN RAISE EXCEPTION 'Appointment worklist access denied'; END IF;
  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'Select an active facility to access the appointment worklist';
  END IF;

  RETURN QUERY
  SELECT
    a.id, a.patient_id, p.patient_code, p.first_name, p.last_name, a.scheduled_at,
    coalesce(a.consultation_type,'General Consultation'), a.practitioner_id,
    nullif(pg_catalog.btrim(pg_catalog.concat_ws(' ',pr.first_name,pr.last_name)),''),
    a.department, a.reason, a.status, a.attending_officer_id, a.treatment_status, a.treatment_notes
  FROM public.appointments a
  JOIN public.patients p ON p.id = a.patient_id
  LEFT JOIN public.profiles pr ON pr.id = a.practitioner_id
  WHERE coalesce(p.status,'active') <> 'inactive'
    AND a.facility_id = v_facility
    AND p.facility_id = v_facility
  ORDER BY a.scheduled_at ASC
  LIMIT v_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_appointment_schedulable_patients(_limit integer DEFAULT 300)
RETURNS TABLE(id uuid, patient_code text, first_name text, last_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_limit integer := greatest(1, least(coalesce(_limit, 300), 500));
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(v_user,'admin'::public.app_role)
    OR public.has_role(v_user,'it_admin'::public.app_role)
    OR public.has_role(v_user,'practitioner'::public.app_role)
    OR public.has_role(v_user,'nurse'::public.app_role)
    OR public.has_role(v_user,'midwife'::public.app_role)
    OR public.has_role(v_user,'specialist_nurse'::public.app_role)
    OR public.has_role(v_user,'front_desk'::public.app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to schedule appointments'; END IF;
  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'Select an active facility to schedule appointments';
  END IF;

  RETURN QUERY
  SELECT p.id, p.patient_code, p.first_name, p.last_name
  FROM public.patients p
  WHERE coalesce(p.status,'active') <> 'inactive'
    AND p.facility_id = v_facility
  ORDER BY p.created_at DESC
  LIMIT v_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_appointment_workflow(
  _patient_id uuid,
  _scheduled_at timestamptz,
  _department text,
  _reason text,
  _consultation_type text,
  _practitioner_id uuid DEFAULT NULL
)
RETURNS public.appointments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  result public.appointments;
  patient_facility uuid;
  uid uuid := auth.uid();
  active_facility uuid := public.current_user_facility_id();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin'::public.app_role)
    OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role)
    OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
    OR public.has_role(uid,'front_desk'::public.app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to schedule appointments'; END IF;

  IF active_facility IS NULL THEN
    RAISE EXCEPTION 'Select an active facility before scheduling an appointment';
  END IF;
  patient_facility := public.assert_patient_facility_context(_patient_id);
  IF patient_facility IS DISTINCT FROM active_facility THEN
    RAISE EXCEPTION 'Patient belongs to a different facility context. Switch to the patient facility and try again';
  END IF;
  IF _scheduled_at IS NULL THEN RAISE EXCEPTION 'Scheduled time is required'; END IF;
  IF NULLIF(pg_catalog.btrim(_consultation_type),'') IS NULL THEN
    RAISE EXCEPTION 'Consultation type is required';
  END IF;
  IF _practitioner_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.profiles p WHERE p.id = _practitioner_id
  ) THEN RAISE EXCEPTION 'Selected clinician does not exist'; END IF;

  INSERT INTO public.appointments(
    patient_id, practitioner_id, department, scheduled_at, duration_minutes, reason,
    status, notes, created_at, updated_at, treatment_status, consultation_type, facility_id
  ) VALUES (
    _patient_id, _practitioner_id, NULLIF(pg_catalog.btrim(_department),''), _scheduled_at,
    30, NULLIF(pg_catalog.btrim(_reason),''), 'scheduled', NULL, pg_catalog.now(),
    pg_catalog.now(), 'scheduled', NULLIF(pg_catalog.btrim(_consultation_type),''), patient_facility
  )
  RETURNING * INTO result;
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_appointment_workflow(
  _patient_id uuid,
  _scheduled_at timestamptz,
  _department text,
  _reason text DEFAULT NULL
)
RETURNS public.appointments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  active_facility uuid := public.current_user_facility_id();
  patient_facility uuid;
  result public.appointments;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin'::public.app_role)
    OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role)
    OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
    OR public.has_role(uid,'front_desk'::public.app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to schedule appointments'; END IF;
  IF active_facility IS NULL THEN
    RAISE EXCEPTION 'Select an active facility before scheduling an appointment';
  END IF;

  SELECT p.facility_id INTO patient_facility
  FROM public.patients p
  WHERE p.id = _patient_id AND coalesce(p.status,'active') <> 'inactive'
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active patient does not exist'; END IF;
  IF patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
  IF patient_facility IS DISTINCT FROM active_facility THEN
    RAISE EXCEPTION 'Patient belongs to a different facility context. Switch to the patient facility and try again';
  END IF;
  IF _scheduled_at IS NULL THEN RAISE EXCEPTION 'Scheduled time is required'; END IF;

  INSERT INTO public.appointments(
    patient_id, practitioner_id, department, scheduled_at, duration_minutes, reason,
    status, notes, created_at, updated_at, treatment_status, facility_id
  ) VALUES (
    _patient_id, CASE WHEN public.has_role(uid,'practitioner'::public.app_role) THEN uid ELSE NULL END,
    NULLIF(pg_catalog.btrim(_department),''), _scheduled_at, 30,
    NULLIF(pg_catalog.btrim(_reason),''), 'scheduled', NULL, pg_catalog.now(),
    pg_catalog.now(), 'scheduled', patient_facility
  )
  RETURNING * INTO result;
  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_appointment_worklist(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_appointment_worklist(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.get_appointment_schedulable_patients(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_appointment_schedulable_patients(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.create_appointment_workflow(uuid,timestamptz,text,text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(uuid,timestamptz,text,text,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_appointment_workflow(uuid,timestamptz,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(uuid,timestamptz,text,text) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
