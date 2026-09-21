-- Retire the legacy role-management RPC from the public API surface.
-- The canonical administrative workflow is admin-create-user plus the server-authorized update_role action.
REVOKE ALL ON FUNCTION public.admin_update_user_role(uuid,public.app_role) FROM PUBLIC,anon,authenticated;
DROP FUNCTION public.admin_update_user_role(uuid,public.app_role);