-- Notification module advisor reconciliation: indexes, RLS init-plan optimization,
-- and explicit service-only boundary documentation for delivery evidence.

-- Cover notification onboarding foreign keys used by admin/IT control-plane lookups.
CREATE INDEX IF NOT EXISTS idx_facility_notification_config_created_by
  ON public.facility_notification_config(created_by);
CREATE INDEX IF NOT EXISTS idx_facility_notification_config_updated_by
  ON public.facility_notification_config(updated_by);
CREATE INDEX IF NOT EXISTS idx_facility_notification_config_verified_by
  ON public.facility_notification_config(verified_by);
CREATE INDEX IF NOT EXISTS idx_facility_notification_provider_connections_created_by
  ON public.facility_notification_provider_connections(created_by);
CREATE INDEX IF NOT EXISTS idx_facility_notification_provider_connections_updated_by
  ON public.facility_notification_provider_connections(updated_by);
CREATE INDEX IF NOT EXISTS idx_facility_notification_provider_connections_verified_by
  ON public.facility_notification_provider_connections(verified_by);
CREATE INDEX IF NOT EXISTS idx_notification_deliveries_user_id
  ON public.notification_deliveries(user_id);

-- Keep client-visible notification RLS policies from re-evaluating auth state per row.
DROP POLICY IF EXISTS "users manage own notification channel preferences" ON public.notification_channel_preferences;
CREATE POLICY "users manage own notification channel preferences"
  ON public.notification_channel_preferences
  FOR ALL TO authenticated
  USING ((user_id = (select auth.uid())) OR (select public.has_role((select auth.uid()),'admin'::public.app_role)))
  WITH CHECK ((user_id = (select auth.uid())) OR (select public.has_role((select auth.uid()),'admin'::public.app_role)));

DROP POLICY IF EXISTS "users manage own push subscriptions" ON public.notification_push_subscriptions;
CREATE POLICY "users manage own push subscriptions"
  ON public.notification_push_subscriptions
  FOR ALL TO authenticated
  USING ((user_id = (select auth.uid())) OR (select public.has_role((select auth.uid()),'admin'::public.app_role)))
  WITH CHECK ((user_id = (select auth.uid())) OR (select public.has_role((select auth.uid()),'admin'::public.app_role)));

-- Facility notification configuration is read by the Settings control plane.
-- IT administrators have the same facility-scoped operational read/write access as admins,
-- while production approval remains administrator-only in the dedicated RPC.
DROP POLICY IF EXISTS "facility notification config scoped read" ON public.facility_notification_config;
DROP POLICY IF EXISTS "facility notification config admin update" ON public.facility_notification_config;
DROP POLICY IF EXISTS "facility notification config access" ON public.facility_notification_config;
DROP POLICY IF EXISTS "facility notification config admin manage" ON public.facility_notification_config;
CREATE POLICY "facility notification config access"
  ON public.facility_notification_config
  FOR SELECT TO authenticated
  USING ((select public.has_facility_access((select auth.uid()),facility_id)));
CREATE POLICY "facility notification config admin manage"
  ON public.facility_notification_config
  FOR ALL TO authenticated
  USING (
    ((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role)))
  )
  WITH CHECK (
    ((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role)))
  );

DROP POLICY IF EXISTS "facility notification provider access" ON public.facility_notification_provider_connections;
DROP POLICY IF EXISTS "facility notification provider admin manage" ON public.facility_notification_provider_connections;
DROP POLICY IF EXISTS "facility notification provider admin read" ON public.facility_notification_provider_connections;
DROP POLICY IF EXISTS "facility notification provider admin update" ON public.facility_notification_provider_connections;
CREATE POLICY "facility notification provider access"
  ON public.facility_notification_provider_connections
  FOR SELECT TO authenticated
  USING (
    ((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role)))
  );
CREATE POLICY "facility notification provider admin manage"
  ON public.facility_notification_provider_connections
  FOR ALL TO authenticated
  USING (
    ((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role)))
  )
  WITH CHECK (
    ((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role)))
  );

COMMENT ON TABLE public.notification_deliveries IS
  'Service/provider delivery evidence. RLS is enabled with no client policies intentionally; provider workers and trusted service-role processes access delivery records. Do not add broad authenticated access.';
