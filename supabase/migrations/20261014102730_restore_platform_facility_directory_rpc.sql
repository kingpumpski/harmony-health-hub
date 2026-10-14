-- Restore the canonical platform facility directory RPC and keep the legacy alias functional.
-- This migration is safe to re-run and does not modify facility or patient rows.
BEGIN;

CREATE OR REPLACE FUNCTION public.platform_list_facilities()
RETURNS TABLE(
  id uuid,
  name text,
  facility_code text,
  facility_type text,
  district text,
  region text,
  is_active boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    WHERE ur.user_id = (SELECT auth.uid())
      AND ur.role = 'system_superuser'::public.app_role
  ) THEN
    RAISE EXCEPTION 'Only system super administrators may view platform facilities';
  END IF;

  RETURN QUERY
  SELECT hf.id, hf.name, hf.facility_code, hf.facility_type,
         hf.district, hf.region, hf.is_active, hf.created_at
  FROM public.healthcare_facilities hf
  ORDER BY hf.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.platform_list_facilitys()
RETURNS TABLE(
  id uuid,
  name text,
  facility_code text,
  facility_type text,
  district text,
  region text,
  is_active boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    WHERE ur.user_id = (SELECT auth.uid())
      AND ur.role = 'system_superuser'::public.app_role
  ) THEN
    RAISE EXCEPTION 'Only system super administrators may view platform facilities';
  END IF;

  RETURN QUERY SELECT * FROM public.platform_list_facilities();
END;
$function$;

REVOKE ALL ON FUNCTION public.platform_list_facilities() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.platform_list_facilitys() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.platform_list_facilities() TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_list_facilitys() TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;