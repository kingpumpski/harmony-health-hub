-- Contract tests for operational workspace scope hardening.
DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public.get_laboratory_workspace(integer)'::regprocedure) INTO d;
  IF position('v_department' in d)=0 OR position('laboratory' in d)=0 THEN RAISE EXCEPTION 'laboratory department boundary missing'; END IF;
  IF has_function_privilege('anon','public.get_laboratory_workspace(integer)','EXECUTE') THEN RAISE EXCEPTION 'anon must not execute laboratory workspace'; END IF;

  SELECT pg_get_functiondef('public.get_imaging_workspace(integer)'::regprocedure) INTO d;
  IF position('v_department' in d)=0 OR position('radiology' in d)=0 THEN RAISE EXCEPTION 'imaging department boundary missing'; END IF;
  IF has_function_privilege('anon','public.get_imaging_workspace(integer)','EXECUTE') THEN RAISE EXCEPTION 'anon must not execute imaging workspace'; END IF;

  SELECT pg_get_functiondef('public.get_pharmacy_workspace(integer)'::regprocedure) INTO d;
  IF position('v_pharmacist' in d)=0 OR position('ELSE ''[]''::jsonb END' in d)=0 THEN RAISE EXCEPTION 'pharmacy least-privilege projection missing'; END IF;
  IF has_function_privilege('anon','public.get_pharmacy_workspace(integer)','EXECUTE') THEN RAISE EXCEPTION 'anon must not execute pharmacy workspace'; END IF;

  SELECT pg_get_functiondef('public.get_admission_workspace(integer)'::regprocedure) INTO d;
  IF position('current_user_facility_id' in d)=0 OR position('ward_beds' in d)=0 THEN RAISE EXCEPTION 'admission facility boundary missing'; END IF;
  IF has_function_privilege('anon','public.get_admission_workspace(integer)','EXECUTE') THEN RAISE EXCEPTION 'anon must not execute admission workspace'; END IF;

  SELECT pg_get_functiondef('public.get_operational_workspace(text,integer)'::regprocedure) INTO d;
  IF position('lower(trim(a.department))=v_department' in d)=0 THEN RAISE EXCEPTION 'appointment department boundary missing'; END IF;
  IF position('ELSIF _module=''ward''' in d)=0 OR position('ELSIF _module=''insurance''' in d)=0 THEN RAISE EXCEPTION 'existing operational branches were lost'; END IF;
  IF has_function_privilege('anon','public.get_operational_workspace(text,integer)','EXECUTE') THEN RAISE EXCEPTION 'anon must not execute operational workspace'; END IF;
END $$;