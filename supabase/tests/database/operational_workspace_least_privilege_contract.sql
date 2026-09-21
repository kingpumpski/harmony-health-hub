DO $$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.get_operational_workspace(text,integer)'::regprocedure) INTO d;
 IF position('Authentication required' IN d)=0 THEN RAISE EXCEPTION 'Operational workspace authentication guard missing'; END IF;
 IF position('JOIN patients p ON p.id=a.patient_id' IN d)=0 THEN RAISE EXCEPTION 'Appointment patient linkage missing'; END IF;
 IF position('JOIN patients p ON p.id=h.patient_id' IN d)=0 THEN RAISE EXCEPTION 'Handover patient linkage missing'; END IF;
 IF position('JOIN patients p ON p.id=i.patient_id' IN d)=0 THEN RAISE EXCEPTION 'Insurance patient linkage missing'; END IF;
 IF position('JOIN patients p ON p.id=m.patient_id' IN d)=0 THEN RAISE EXCEPTION 'MAR patient linkage missing'; END IF;
 IF has_function_privilege('anon','public.get_operational_workspace(text,integer)','EXECUTE') THEN RAISE EXCEPTION 'anon must not execute operational workspace'; END IF;
END $$;