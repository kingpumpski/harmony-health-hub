-- Allow IT Admin support workflows to inspect rollout decisions for troubleshooting.
-- Use bigint before abs() to avoid integer overflow for hashtext's minimum value.
CREATE OR REPLACE FUNCTION public.notification_feature_enabled(_key TEXT, _user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  f public.notification_feature_flags;
  bucket INTEGER;
  caller_id UUID := (SELECT auth.uid());
  caller_role TEXT := current_setting('request.jwt.claim.role', true);
BEGIN
  IF caller_id IS NULL AND caller_role IS DISTINCT FROM 'service_role' THEN
    RETURN FALSE;
  END IF;

  IF caller_id IS NOT NULL THEN
    _user_id := COALESCE(_user_id, caller_id);
    IF _user_id IS DISTINCT FROM caller_id
       AND NOT (
         public.has_role(caller_id, 'admin'::public.app_role)
         OR public.has_role(caller_id, 'it_admin'::public.app_role)
         OR public.has_role(caller_id, 'system_superuser'::public.app_role)
       ) THEN
      RAISE EXCEPTION 'Forbidden';
    END IF;
  ELSIF _user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT * INTO f
  FROM public.notification_feature_flags
  WHERE key = _key;

  IF NOT FOUND OR NOT f.enabled OR f.kill_switch THEN
    RETURN FALSE;
  END IF;

  IF f.rollout_percent >= 100 THEN
    RETURN TRUE;
  END IF;

  IF _user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  bucket := mod(abs(hashtext(_user_id::text || ':' || _key)::BIGINT), 100)::INTEGER;
  RETURN bucket < f.rollout_percent;
END;
$function$;

REVOKE ALL ON FUNCTION public.notification_feature_enabled(TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.notification_feature_enabled(TEXT, UUID) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
