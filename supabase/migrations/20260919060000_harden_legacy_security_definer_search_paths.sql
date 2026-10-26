-- Harden legacy SECURITY DEFINER routines created with search_path=public.
-- Empty search_path prevents object shadowing; function bodies use schema-qualified objects.
ALTER FUNCTION public.admin_update_user_role(uuid, public.app_role) SET search_path = '';
ALTER FUNCTION public.create_appointment_workflow(uuid, timestamptz, text, text) SET search_path = '';
ALTER FUNCTION public.record_triage_assessment(uuid, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, text, text, text, text) SET search_path = '';
