-- Close explicit PUBLIC execution exposure for previously hardened clinical SECURITY DEFINER RPCs.
REVOKE EXECUTE ON FUNCTION public.create_emergency_case(uuid,text,text,text,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_dental_record(uuid,text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_anesthetic_assessment(uuid,text,text,text,text,text,text,text,text,boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_patient_appointment(uuid,timestamptz,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_inpatient_review(uuid,text,text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_maternity_episode_workflow(uuid,integer,integer,date,date,text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_fertility_cycle_workflow(uuid,text,text,date,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_meal_plan_workflow(uuid,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_nursing_care_plan(uuid,text,text,text,text,uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_triage_assessment(uuid,integer,integer,integer,numeric,integer,numeric,numeric,numeric,integer,text,text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.schedule_medication_administration(uuid,text,text,text,timestamptz,text,integer) FROM PUBLIC;
NOTIFY pgrst,'reload schema';