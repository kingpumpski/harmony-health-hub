-- Ensure discharge validates admission existence before patient facility context.
DO $m$
DECLARE v_sql text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_sql
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname='discharge_admission_workflow'
  LIMIT 1;
  v_sql:=replace(v_sql,
    'PERFORM public.assert_patient_facility_context(v_admission.patient_id);\n  IF v_admission.id IS NULL THEN',
    'IF v_admission.id IS NULL THEN');
  v_sql:=replace(v_sql,
    'RAISE EXCEPTION ''Admission not found'';\n  END IF;',
    'RAISE EXCEPTION ''Admission not found'';\n  END IF;\n  PERFORM public.assert_patient_facility_context(v_admission.patient_id);');
  EXECUTE v_sql;
END$m$;
NOTIFY pgrst,'reload schema';