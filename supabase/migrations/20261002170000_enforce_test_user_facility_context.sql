BEGIN;

-- Avoid a nested helper dependency for the test-mode identity check. This is
-- used by the canonical facility resolver and must reliably read the runtime
-- flag and test-user allowlist under the function's definer privileges.
CREATE OR REPLACE FUNCTION public.hms_current_user_is_test_user()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT (SELECT auth.uid()) IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.hms_test_runtime r
      WHERE r.id = true AND r.enabled = true
    )
    AND EXISTS (
      SELECT 1
      FROM public.hms_test_users tu
      WHERE tu.user_id = (SELECT auth.uid())
        AND tu.enabled = true
    );
$function$;

CREATE OR REPLACE FUNCTION public.current_user_facility_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT CASE
    WHEN public.hms_current_user_is_test_user()
      THEN public.hms_test_facility_id()
    ELSE COALESCE(
      (
        SELECT uaf.facility_id
        FROM public.user_active_facilities uaf
        JOIN public.facility_memberships fm
          ON fm.user_id = uaf.user_id
         AND fm.facility_id = uaf.facility_id
         AND fm.is_active = true
        WHERE uaf.user_id = (SELECT auth.uid())
          AND EXISTS (
            SELECT 1
            FROM public.healthcare_facilities hf
            WHERE hf.id = uaf.facility_id AND hf.is_active = true
          )
        LIMIT 1
      ),
      (
        SELECT fm.facility_id
        FROM public.facility_memberships fm
        JOIN public.healthcare_facilities hf
          ON hf.id = fm.facility_id AND hf.is_active = true
        WHERE fm.user_id = (SELECT auth.uid()) AND fm.is_active = true
        GROUP BY fm.facility_id
        HAVING count(*) = 1
        ORDER BY fm.facility_id
        LIMIT 1
      )
    )
  END;
$function$;

CREATE OR REPLACE FUNCTION public.get_user_facilities()
RETURNS TABLE(
  facility_id uuid,
  facility_name text,
  facility_code text,
  facility_type text,
  is_active boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_test_facility uuid := public.hms_test_facility_id();
  v_test boolean := public.hms_current_user_is_test_user();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF v_test THEN
    IF v_test_facility IS NULL THEN
      RAISE EXCEPTION 'Test mode is enabled but the Harmony Health Hub Test Facility (TEST-0001) is not configured';
    END IF;
    RETURN QUERY
      SELECT hf.id, hf.name, hf.facility_code, hf.facility_type, hf.is_active
      FROM public.healthcare_facilities hf
      WHERE hf.id = v_test_facility AND hf.is_active = true;
    RETURN;
  END IF;

  IF public.current_user_has_role('system_superuser') THEN
    RETURN QUERY
      SELECT hf.id, hf.name, hf.facility_code, hf.facility_type, hf.is_active
      FROM public.healthcare_facilities hf
      WHERE hf.is_active = true
      ORDER BY hf.name, hf.id;
  ELSE
    RETURN QUERY
      SELECT hf.id, hf.name, hf.facility_code, hf.facility_type, hf.is_active
      FROM public.healthcare_facilities hf
      WHERE hf.is_active = true AND hf.id = v_facility
      LIMIT 1;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_active_facility_context(_facility_id uuid)
RETURNS public.healthcare_facilities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  result public.healthcare_facilities;
  v_test boolean := public.hms_current_user_is_test_user();
  v_test_facility uuid := public.hms_test_facility_id();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF v_test AND _facility_id IS DISTINCT FROM v_test_facility THEN
    RAISE EXCEPTION 'Test mode restricts this account to the Harmony Health Hub Test Facility (TEST-0001)';
  END IF;

  SELECT * INTO result
  FROM public.healthcare_facilities hf
  WHERE hf.id = _facility_id AND hf.is_active = true;

  IF result.id IS NULL THEN
    RAISE EXCEPTION 'Active facility is required';
  END IF;

  IF NOT (
    public.has_role(uid, 'admin'::public.app_role)
    OR public.has_role(uid, 'it_admin'::public.app_role)
    OR (v_test AND _facility_id = v_test_facility)
    OR public.has_facility_access(uid, _facility_id)
  ) THEN
    RAISE EXCEPTION 'Facility access required';
  END IF;

  INSERT INTO public.user_active_facilities(user_id, facility_id, updated_at)
  VALUES (uid, _facility_id, pg_catalog.now())
  ON CONFLICT (user_id) DO UPDATE
    SET facility_id = EXCLUDED.facility_id, updated_at = EXCLUDED.updated_at;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.hms_current_user_is_test_user() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_user_facility_id() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_user_facilities() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_facilities() TO authenticated;
REVOKE ALL ON FUNCTION public.set_active_facility_context(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_active_facility_context(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
