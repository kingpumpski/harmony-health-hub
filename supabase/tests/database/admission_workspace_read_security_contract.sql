DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(
    'public.get_admission_workspace(integer)'::regprocedure
  ) INTO d;

  IF position('Authentication required' IN d) = 0 THEN
    RAISE EXCEPTION 'Admission workspace authentication guard missing';
  END IF;

  IF position('JOIN public.patients p ON p.id = a.patient_id' IN d) = 0 THEN
    RAISE EXCEPTION 'Admission workspace patient linkage missing';
  END IF;

  IF position('p.status <> ''inactive''' IN d) = 0 THEN
    RAISE EXCEPTION 'Inactive patient filtering missing';
  END IF;

  IF has_function_privilege(
    'anon',
    'public.get_admission_workspace(integer)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon must not execute admission workspace';
  END IF;

  IF has_table_privilege('anon', 'public.admissions', 'SELECT') THEN
    RAISE EXCEPTION 'anon must not directly select admissions';
  END IF;
END $$;
