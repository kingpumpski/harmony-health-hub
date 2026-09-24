BEGIN
  DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public.get_operational_workspace(text,integer)'::regprocedure) INTO d;
  IF position('ELSIF _module=''medication_administration''' IN d)=0 THEN RAISE EXCEPTION 'Medication administration workspace branch missing'; END IF;
  IF position('jsonb_build_object(''records''' IN d)=0 THEN RAISE EXCEPTION 'Medication administration records projection missing'; END IF;
  IF position('''profiles''' IN d)>0 OR position('FROM profiles' IN d)>0 THEN RAISE EXCEPTION 'Medication administration workspace must not expose profiles projection'; END IF;
  IF has_function_privilege('anon','public.get_operational_workspace(text,integer)','EXECUTE') THEN RAISE EXCEPTION 'anon must not execute operational workspace'; END IF;
END;