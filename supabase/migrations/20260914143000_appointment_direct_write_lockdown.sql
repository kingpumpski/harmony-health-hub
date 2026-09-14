-- Make appointment state server-authoritative through the existing workflow RPCs.
-- The application already exposes authenticated lifecycle RPCs for creation,
-- claiming, encounter start, and workflow updates, so direct table mutation
-- is no longer required by the operational contract.

REVOKE INSERT, UPDATE, DELETE ON public.appointments FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.appointments FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.appointments FROM PUBLIC;

REVOKE ALL ON FUNCTION public.claim_appointment(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_appointment_workflow(uuid,timestamp with time zone,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_patient_appointment(uuid,timestamp with time zone,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.start_appointment_encounter(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_appointment_workflow(uuid,timestamp with time zone,text,text,text,text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.claim_appointment(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_appointment_workflow(uuid,timestamp with time zone,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_appointment(uuid,timestamp with time zone,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_appointment_encounter(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_appointment_workflow(uuid,timestamp with time zone,text,text,text,text) TO authenticated;

COMMENT ON TABLE public.appointments IS 'Appointment lifecycle is server-authoritative through authenticated workflow RPCs.';
