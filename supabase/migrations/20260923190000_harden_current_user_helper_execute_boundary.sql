-- Current-user authorization helpers are safe for authenticated execution:
-- they derive the subject exclusively from auth.uid() and accept no arbitrary
-- user ID. RLS policies call these functions directly, so authenticated EXECUTE
-- must remain granted. PUBLIC and anon access remain revoked.
REVOKE ALL ON FUNCTION public.current_user_has_role(public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_has_role(public.app_role) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_user_is_clinical_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_is_clinical_staff() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.current_user_can_edit_patient_record() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_can_edit_patient_record() TO authenticated, service_role;
