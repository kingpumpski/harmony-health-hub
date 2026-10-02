-- Ensure Patient Hub read-only RPCs can be invoked with PostgREST GET.
-- The frontend intentionally uses { get: true } for these read-only functions;
-- PostgREST rejects GET with 405 when the installed function volatility is VOLATILE.
BEGIN;

ALTER FUNCTION public.get_patient_appointments(uuid, integer) STABLE;
ALTER FUNCTION public.get_patient_admission_history(uuid) STABLE;
ALTER FUNCTION public.get_patient_hub_clinical_snapshot(uuid) STABLE;
ALTER FUNCTION public.get_patient_current_treatment_snapshot(uuid, uuid) STABLE;
ALTER FUNCTION public.get_patient_bmi_context(uuid) STABLE;
ALTER FUNCTION public.get_attending_patient_history(uuid, uuid) STABLE;

NOTIFY pgrst, 'reload schema';
COMMIT;
