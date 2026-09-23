-- Prevent authenticated clients from directly probing current-user authorization helpers.
-- These helpers are internal policy/RPC dependencies; exposed client RPCs perform
-- their own role checks and do not require direct helper execution.

REVOKE EXECUTE ON FUNCTION public.current_user_has_role(public.app_role)
  FROM authenticated, anon, public;

REVOKE EXECUTE ON FUNCTION public.current_user_is_clinical_staff()
  FROM authenticated, anon, public;

REVOKE EXECUTE ON FUNCTION public.current_user_can_edit_patient_record()
  FROM authenticated, anon, public;
