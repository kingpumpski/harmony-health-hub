DO $migration$
DECLARE v_sql text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_sql
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='register_patient_workflow'
    AND pg_get_function_identity_arguments(p.oid)='jsonb';
  v_sql := replace(v_sql,
    'IF _patient IS NULL OR jsonb_typeof(_patient) <> ''object'' THEN RAISE EXCEPTION ''Patient payload is required''; END IF;',
    'IF _patient IS NULL OR jsonb_typeof(_patient) <> ''object'' THEN RAISE EXCEPTION ''Patient payload is required''; END IF;
 IF public.current_user_facility_id() IS NULL THEN RAISE EXCEPTION ''Active facility context is required''; END IF;');
  v_sql := replace(v_sql,
    'emergency_contact_relation,created_by)',
    'emergency_contact_relation,created_by,facility_id)');
  v_sql := replace(v_sql,
    'uid) ON CONFLICT (id) DO NOTHING',
    'uid,public.current_user_facility_id()) ON CONFLICT (id) DO NOTHING');
  v_sql := replace(v_sql, 'SET search_path TO ''pg_catalog'', ''public''', 'SET search_path TO ''''');
  EXECUTE v_sql;

  SELECT pg_get_functiondef(p.oid) INTO v_sql
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='set_patient_insurance_company'
    AND pg_get_function_identity_arguments(p.oid)='uuid,uuid';
  v_sql := replace(v_sql,
    'IF _patient_id IS NULL THEN RAISE EXCEPTION ''Patient is required''; END IF;',
    'IF _patient_id IS NULL THEN RAISE EXCEPTION ''Patient is required''; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);');
  v_sql := replace(v_sql, 'SET search_path TO ''pg_catalog'', ''public''', 'SET search_path TO ''''');
  EXECUTE v_sql;

  SELECT pg_get_functiondef(p.oid) INTO v_sql
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='enter_lab_result'
    AND pg_get_function_identity_arguments(p.oid)='uuid,text,numeric,text,boolean';
  v_sql := replace(v_sql,
    'IF NOT FOUND THEN RAISE EXCEPTION ''Laboratory order not found''; END IF;',
    'IF NOT FOUND THEN RAISE EXCEPTION ''Laboratory order not found''; END IF;
 PERFORM public.assert_patient_facility_context(o.patient_id);');
  v_sql := replace(v_sql, 'SET search_path TO ''pg_catalog'', ''public''', 'SET search_path TO ''''');
  EXECUTE v_sql;

  SELECT pg_get_functiondef(p.oid) INTO v_sql
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='discharge_admission_workflow'
    AND pg_get_function_identity_arguments(p.oid)='uuid,text';
  v_sql := replace(v_sql,
    'IF v_admission.id IS NULL THEN RAISE EXCEPTION ''Admission not found''; END IF;',
    'IF v_admission.id IS NULL THEN RAISE EXCEPTION ''Admission not found''; END IF;
 PERFORM public.assert_patient_facility_context(v_admission.patient_id);');
  v_sql := replace(v_sql, 'SET search_path TO ''pg_catalog'', ''public''', 'SET search_path TO ''''');
  EXECUTE v_sql;

  SELECT pg_get_functiondef(p.oid) INTO v_sql
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='transfer_patient_ward_bed_workflow'
    AND pg_get_function_identity_arguments(p.oid)='uuid,uuid,uuid,uuid,text,text';
  v_sql := replace(v_sql,
    'IF v_admission.id IS NULL THEN RAISE EXCEPTION ''Active admission not found for patient''; END IF;',
    'IF v_admission.id IS NULL THEN RAISE EXCEPTION ''Active admission not found for patient''; END IF;
 PERFORM public.assert_patient_facility_context(_patient_id);');
  v_sql := replace(v_sql, 'SET search_path TO ''pg_catalog'', ''public''', 'SET search_path TO ''''');
  EXECUTE v_sql;
END
$migration$;

ALTER FUNCTION public.register_patient_workflow(jsonb) SET search_path = '';
ALTER FUNCTION public.set_patient_insurance_company(uuid,uuid) SET search_path = '';
ALTER FUNCTION public.enter_lab_result(uuid,text,numeric,text,boolean) SET search_path = '';
ALTER FUNCTION public.discharge_admission_workflow(uuid,text) SET search_path = '';
ALTER FUNCTION public.transfer_patient_ward_bed_workflow(uuid,uuid,uuid,uuid,text,text) SET search_path = '';
NOTIFY pgrst, 'reload schema';