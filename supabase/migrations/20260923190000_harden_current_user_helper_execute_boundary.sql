-- Keep current-user helpers executable by authenticated because RLS policies
-- invoke them directly. They accept no arbitrary user ID, so they do not expose
-- cross-user role probing. Anonymous and PUBLIC execution remains revoked.

REVOKE EXECUTE ON FUNCTION public.current_user_has_role(public.app_role)
  FROM anon, public;

REVOKE EXECUTE ON FUNCTION public.current_user_is_clinical_staff()
  FROM authenticated, anon, public;

REVOKE EXECUTE ON FUNCTION public.current_user_can_edit_patient_record()
  FROM authenticated, anon, public;
