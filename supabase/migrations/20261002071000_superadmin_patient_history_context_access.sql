-- Permit the system super admin to inspect records only within the explicitly selected facility context.
DO $migration$
DECLARE v_definition text;
BEGIN
  v_definition := pg_catalog.pg_get_functiondef('public.assert_patient_facility_read_context(uuid)'::regprocedure);
  v_definition := replace(v_definition,
    'IF public.has_role(uid,''admin''::public.app_role)',
    'IF public.has_role(uid,''admin''::public.app_role) OR public.has_role(uid,''system_superuser''::public.app_role)');
  IF v_definition = pg_catalog.pg_get_functiondef('public.assert_patient_facility_read_context(uuid)'::regprocedure) THEN
    RAISE EXCEPTION 'Could not patch patient facility read-context authorization';
  END IF;
  EXECUTE v_definition;

  v_definition := pg_catalog.pg_get_functiondef('public.get_patient_profile_for_user(uuid)'::regprocedure);
  v_definition := replace(v_definition,
    'OR public.has_role(uid, ''admin''::public.app_role)',
    'OR public.has_role(uid, ''admin''::public.app_role)' || chr(10) || '    OR public.has_role(uid, ''system_superuser''::public.app_role)');
  IF position('system_superuser' IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not patch patient profile role gate'; END IF;
  EXECUTE v_definition;

  v_definition := pg_catalog.pg_get_functiondef('public.get_patient_appointments(uuid,integer)'::regprocedure);
  v_definition := replace(v_definition,
    'public.has_role(auth.uid(),''admin'')',
    'public.has_role(auth.uid(),''admin'') OR public.has_role(auth.uid(),''system_superuser'')');
  IF position('system_superuser' IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not patch patient appointments role gate'; END IF;
  EXECUTE v_definition;

  v_definition := pg_catalog.pg_get_functiondef('public.get_patient_hub_clinical_snapshot(uuid)'::regprocedure);
  v_definition := replace(v_definition,
    'is_core:=public.has_role(uid,''admin'')',
    'is_core:=public.has_role(uid,''admin'') OR public.has_role(uid,''system_superuser'')');
  IF position('system_superuser' IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not patch patient clinical snapshot role gate'; END IF;
  EXECUTE v_definition;

  v_definition := pg_catalog.pg_get_functiondef('public.get_patient_admission_history(uuid)'::regprocedure);
  v_definition := replace(v_definition,
    'v_role NOT IN (''admin'',''it_admin'',''practitioner'',''nurse'',''midwife'',''specialist_nurse'')',
    'v_role NOT IN (''admin'',''it_admin'',''system_superuser'',''practitioner'',''nurse'',''midwife'',''specialist_nurse'')');
  IF position('system_superuser' IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not patch patient admission role gate'; END IF;
  EXECUTE v_definition;

  v_definition := pg_catalog.pg_get_functiondef('public.start_appointment_encounter(uuid,text,text)'::regprocedure);
  v_definition := replace(v_definition,
    'OR public.has_role(v_user, ''it_admin''::public.app_role);',
    'OR public.has_role(v_user, ''it_admin''::public.app_role) OR public.has_role(v_user, ''system_superuser''::public.app_role);');
  IF position('system_superuser' IN v_definition) = 0 THEN RAISE EXCEPTION 'Could not patch encounter privileged-role gate'; END IF;
  EXECUTE v_definition;
END;
$migration$;
