-- Close the dietary/meal authorization gap left by the legacy role-only RLS policies.
-- The tables predate the next-generation facility/module boundary and do not carry
-- facility_id, so authorization is derived from an active facility membership.

CREATE OR REPLACE FUNCTION private.hms_user_has_dietary_facility_permission(_action text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.facility_memberships fm
    WHERE fm.user_id = (SELECT auth.uid())
      AND fm.is_active = true
      AND public.hms_has_permission(fm.facility_id, 'dietary-restaurant', lower(_action))
  );
$$;

REVOKE ALL ON FUNCTION private.hms_user_has_dietary_facility_permission(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.hms_user_has_dietary_facility_permission(text) TO authenticated;

DROP POLICY IF EXISTS "mp_staff_all" ON public.meal_plans;
CREATE POLICY "mp_staff_all" ON public.meal_plans
  FOR ALL TO authenticated
  USING (
    private.hms_user_has_dietary_facility_permission('write')
    AND (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'canteen'::public.app_role))
  )
  WITH CHECK (
    private.hms_user_has_dietary_facility_permission('write')
    AND (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'canteen'::public.app_role))
  );

DROP POLICY IF EXISTS "mo_staff_all" ON public.meal_orders;
CREATE POLICY "mo_staff_all" ON public.meal_orders
  FOR ALL TO authenticated
  USING (
    private.hms_user_has_dietary_facility_permission('write')
    AND (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'canteen'::public.app_role))
  )
  WITH CHECK (
    private.hms_user_has_dietary_facility_permission('write')
    AND (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'canteen'::public.app_role))
  );

COMMENT ON FUNCTION private.hms_user_has_dietary_facility_permission(text)
IS 'Dietary compatibility bridge for legacy meal tables without facility_id. Requires active facility membership plus canonical HMS dietary-restaurant permission.';
