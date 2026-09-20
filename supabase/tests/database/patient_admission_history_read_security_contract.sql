DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(
    'public.get_patient_admission_history(uuid)'::regprocedure
  ) INTO d;

  IF position('Authentication required' IN d) = 0 THEN
    RAISE EXCEPTION 'Patient admission history authentication guard missing';
  END IF;

  IF position('p.status <> ''inactive''' IN d) = 0 THEN
    RAISE EXCEPTION 'Inactive patient guard missing';
  END IF;

  IF position('a.patient_id = _patient_id' IN d) = 0 THEN
    RAISE EXCEPTION 'Patient admission scope missing';
  END IF;

  IF has_function_privilege(
    'anon',
    'public.get_patient_admission_history(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute patient admission history RPC';
  END IF;
END $$;
