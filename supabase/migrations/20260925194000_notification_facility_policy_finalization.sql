-- Final notification facility-policy reconciliation after control-plane migrations.
-- Replaces legacy admin-only/direct-auth policies left by earlier onboarding migrations.

DROP POLICY IF EXISTS "facility notification config scoped read" ON public.facility_notification_config;
DROP POLICY IF EXISTS "facility notification config admin update" ON public.facility_notification_config;
DROP POLICY IF EXISTS "facility notification config access" ON public.facility_notification_config;
DROP POLICY IF EXISTS "facility notification config admin manage" ON public.facility_notification_config;
CREATE POLICY "facility notification config access" ON public.facility_notification_config
  FOR SELECT TO authenticated
  USING ((select public.has_facility_access((select auth.uid()),facility_id)));
CREATE POLICY "facility notification config admin manage" ON public.facility_notification_config
  FOR ALL TO authenticated
  USING (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))))
  WITH CHECK (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))));

DROP POLICY IF EXISTS "facility notification provider admin read" ON public.facility_notification_provider_connections;
DROP POLICY IF EXISTS "facility notification provider admin update" ON public.facility_notification_provider_connections;
DROP POLICY IF EXISTS "facility notification provider access" ON public.facility_notification_provider_connections;
DROP POLICY IF EXISTS "facility notification provider admin manage" ON public.facility_notification_provider_connections;
CREATE POLICY "facility notification provider access" ON public.facility_notification_provider_connections
  FOR SELECT TO authenticated
  USING (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))));
CREATE POLICY "facility notification provider admin manage" ON public.facility_notification_provider_connections
  FOR ALL TO authenticated
  USING (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))))
  WITH CHECK (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))));
