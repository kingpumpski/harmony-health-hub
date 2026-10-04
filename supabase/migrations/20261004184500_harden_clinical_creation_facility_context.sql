-- Harden clinical creation RPCs with patient facility attribution and fixed search paths.
-- Prevent authenticated callers from creating emergency, dental, or anaesthetic records
-- against a patient outside the caller's permitted facility context.

CREATE OR REPLACE FUNCTION public.create_emergency_case(
  _patient_id uuid,
  _chief_complaint text,
  _acuity text DEFAULT 'urgent'::text,
  _arrival_mode text DEFAULT 'walk_in'::text,
  _assigned_officer uuid DEFAULT NULL::uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
  v_assigned uuid;
  v_priority text;
  v_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'front_desk')
  ) THEN RAISE EXCEPTION 'Emergency operations role required'; END IF;
  IF _patient_id IS NULL OR NULLIF(pg_catalog.btrim(_chief_complaint),'') IS NULL
    THEN RAISE EXCEPTION 'Patient and chief complaint are required'; END IF;

  v_facility := public.assert_patient_facility_context(_patient_id);

  IF _acuity NOT IN ('resuscitation','emergency','urgent','less_urgent','non_urgent')
    THEN RAISE EXCEPTION 'Invalid emergency acuity'; END IF;
  IF _arrival_mode NOT IN ('walk_in','ambulance','referral','other')
    THEN RAISE EXCEPTION 'Invalid emergency arrival mode'; END IF;
  IF _assigned_officer IS NOT NULL AND _assigned_officer <> uid
     AND NOT public.has_role(uid,'admin') AND NOT public.has_role(uid,'it_admin')
    THEN RAISE EXCEPTION 'Only an administrator may assign another officer during creation'; END IF;

  v_priority := CASE _acuity
    WHEN 'resuscitation' THEN 'critical'
    WHEN 'emergency' THEN 'critical'
    WHEN 'urgent' THEN 'urgent'
    WHEN 'less_urgent' THEN 'moderate'
    ELSE 'routine'
  END;
  v_assigned := coalesce(_assigned_officer,uid);

  INSERT INTO public.emergency_cases(
    patient_id, facility_id, arrival_mode, triage_priority, chief_complaint,
    assigned_officer, status
  )
  VALUES(
    _patient_id, v_facility, _arrival_mode, v_priority,
    pg_catalog.btrim(_chief_complaint), v_assigned, 'waiting'
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_dental_record(
  _patient_id uuid,
  _examination text,
  _treatment_plan text,
  _procedures_performed text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_id uuid;
  v_facility uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'it_admin')
    OR public.has_role(auth.uid(),'practitioner')
  ) THEN RAISE EXCEPTION 'Authorized clinical role required'; END IF;

  v_facility := public.assert_patient_facility_context(_patient_id);

  INSERT INTO public.dental_records(
    patient_id, facility_id, examination, treatment_plan,
    procedures_performed, performed_by
  )
  VALUES (
    _patient_id, v_facility,
    NULLIF(pg_catalog.btrim(_examination),''),
    NULLIF(pg_catalog.btrim(_treatment_plan),''),
    NULLIF(pg_catalog.btrim(_procedures_performed),''),
    auth.uid()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_anesthetic_assessment(
  _patient_id uuid,
  _asa_class text DEFAULT 'I'::text,
  _airway_assessment text DEFAULT NULL::text,
  _cardiovascular text DEFAULT NULL::text,
  _respiratory text DEFAULT NULL::text,
  _allergies text DEFAULT NULL::text,
  _medications text DEFAULT NULL::text,
  _fasting_status text DEFAULT NULL::text,
  _conclusions text DEFAULT NULL::text,
  _cleared_for_procedure boolean DEFAULT false
)
RETURNS public.anesthetic_assessments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  result public.anesthetic_assessments;
  v_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Not authorized to create anesthetic assessments'; END IF;

  v_facility := public.assert_patient_facility_context(_patient_id);

  IF NULLIF(pg_catalog.btrim(_asa_class),'') IS NULL
    THEN RAISE EXCEPTION 'ASA class is required'; END IF;
  IF pg_catalog.btrim(_asa_class) NOT IN ('I','II','III','IV','V','VI')
    THEN RAISE EXCEPTION 'Invalid ASA class'; END IF;

  INSERT INTO public.anesthetic_assessments(
    patient_id, facility_id, asa_class, airway_assessment, cardiovascular,
    respiratory, allergies, medications, fasting_status, conclusions,
    cleared_for_procedure, cleared_by, assessed_by, status
  )
  VALUES (
    _patient_id, v_facility, pg_catalog.btrim(_asa_class),
    NULLIF(pg_catalog.btrim(_airway_assessment),''),
    NULLIF(pg_catalog.btrim(_cardiovascular),''),
    NULLIF(pg_catalog.btrim(_respiratory),''),
    NULLIF(pg_catalog.btrim(_allergies),''),
    NULLIF(pg_catalog.btrim(_medications),''),
    NULLIF(pg_catalog.btrim(_fasting_status),''),
    NULLIF(pg_catalog.btrim(_conclusions),''),
    coalesce(_cleared_for_procedure,false),
    CASE WHEN coalesce(_cleared_for_procedure,false) THEN uid ELSE NULL END,
    uid, 'completed'
  )
  RETURNING * INTO result;

  RETURN result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.create_emergency_case(uuid,text,text,text,uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_dental_record(uuid,text,text,text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_anesthetic_assessment(uuid,text,text,text,text,text,text,text,text,boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.create_emergency_case(uuid,text,text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_dental_record(uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_anesthetic_assessment(uuid,text,text,text,text,text,text,text,text,boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';
