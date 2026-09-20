-- Contract tests for clinical workspace read hardening.
DO $
BEGIN
  IF has_function_privilege('anon','public.get_imaging_workspace(integer)','EXECUTE') THEN RAISE EXCEPTION 'anon must not execute imaging workspace'; END IF;
  IF has_function_privilege('anon','public.get_laboratory_workspace(integer)','EXECUTE') THEN RAISE EXCEPTION 'anon must not execute laboratory workspace'; END IF;
  IF has_function_privilege('anon','public.get_pharmacy_workspace(integer)','EXECUTE') THEN RAISE EXCEPTION 'anon must not execute pharmacy workspace'; END IF;
END $;
