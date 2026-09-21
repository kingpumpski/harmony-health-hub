DO $$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.get_operational_workspace(text,integer)'::regprocedure) INTO d;
 IF position('ELSIF _module=''emergency''' IN d)=0 THEN RAISE EXCEPTION 'Emergency workspace branch missing'; END IF;
 IF position('ELSIF _module=''nursing_care''' IN d)=0 THEN RAISE EXCEPTION 'Nursing care workspace branch missing'; END IF;
 IF position('JOIN patients p ON p.id=e.patient_id' IN d)=0 THEN RAISE EXCEPTION 'Emergency patient linkage missing'; END IF;
 IF position('JOIN patients p ON p.id=n.patient_id' IN d)=0 THEN RAISE EXCEPTION 'Nursing care patient linkage missing'; END IF;
 IF has_function_privilege('anon','public.get_operational_workspace(text,integer)','EXECUTE') THEN RAISE EXCEPTION 'anon must not execute operational workspace'; END IF;
END $$;