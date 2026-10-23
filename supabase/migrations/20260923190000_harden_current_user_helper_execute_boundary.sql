-- Prevent authenticated clients from directly probing current-user authorization helpers.
-- These helpers are internal policy/RPC dependencies; exposed client RPCs perform
-- their own role checks and do not require direct helper execution.
-- Some legacy chains do not define every helper until a later reconciliation migration,
-- so guard each revoke rather than failing clean replay on a missing optional signature.
DO $$
BEGIN
  IF to_regprocedure('public.current_user_has_role(public.app_role)') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.current_user_has_role(public.app_role) FROM authenticated, anon, public';
  END IF;
  IF to_regprocedure('public.current_user_is_clinical_staff()') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.current_user_is_clinical_staff() FROM authenticated, anon, public';
  END IF;
  IF to_regprocedure('public.current_user_can_edit_patient_record()') IS NOT NULL THEN
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.current_user_can_edit_patient_record() FROM authenticated, anon, public';
  END IF;
END;
$$;
