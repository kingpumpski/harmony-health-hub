-- Canonical caller-role resolver for authenticated Edge Functions.
BEGIN;
CREATE OR REPLACE FUNCTION public.get_current_user_roles()
RETURNS public.app_role[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT COALESCE(array_agg(ur.role ORDER BY ur.created_at), ARRAY[]::public.app_role[])
  FROM public.user_roles ur
  WHERE ur.user_id = auth.uid();
$function$;
REVOKE ALL ON FUNCTION public.get_current_user_roles() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_current_user_roles() TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
