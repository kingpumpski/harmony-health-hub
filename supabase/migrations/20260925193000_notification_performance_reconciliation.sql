-- Notification performance reconciliation after production control-plane rollout.
-- Keep notification authorization server-scoped while avoiding per-row auth re-evaluation.

CREATE INDEX IF NOT EXISTS idx_facility_notification_config_production_approved_by
  ON public.facility_notification_config(production_approved_by);
CREATE INDEX IF NOT EXISTS idx_notification_audit_actor_id
  ON public.notification_audit(actor_id);
CREATE INDEX IF NOT EXISTS idx_notification_consent_audit_user_id
  ON public.notification_consent_audit(user_id);
CREATE INDEX IF NOT EXISTS idx_notification_delivery_logs_queue_id
  ON public.notification_delivery_logs(queue_id);
CREATE INDEX IF NOT EXISTS idx_notification_delivery_logs_user_id
  ON public.notification_delivery_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_notification_feature_flags_updated_by
  ON public.notification_feature_flags(updated_by);
CREATE INDEX IF NOT EXISTS idx_notification_templates_created_by
  ON public.notification_templates(created_by);
CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_created_by
  ON public.scheduled_notifications(created_by);
CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_user_id
  ON public.scheduled_notifications(user_id);

DROP POLICY IF EXISTS "notification preferences own read" ON public.user_notification_preferences;
CREATE POLICY "notification preferences own read" ON public.user_notification_preferences
  FOR SELECT TO authenticated
  USING ((user_id = (select auth.uid())) OR (select public.has_role((select auth.uid()),'admin'::public.app_role)));
DROP POLICY IF EXISTS "notification preferences own update" ON public.user_notification_preferences;
CREATE POLICY "notification preferences own update" ON public.user_notification_preferences
  FOR UPDATE TO authenticated
  USING ((user_id = (select auth.uid())) OR (select public.has_role((select auth.uid()),'admin'::public.app_role)))
  WITH CHECK ((user_id = (select auth.uid())) OR (select public.has_role((select auth.uid()),'admin'::public.app_role)));
DROP POLICY IF EXISTS "notification preferences own insert" ON public.user_notification_preferences;
CREATE POLICY "notification preferences own insert" ON public.user_notification_preferences
  FOR INSERT TO authenticated
  WITH CHECK ((user_id = (select auth.uid())) OR (select public.has_role((select auth.uid()),'admin'::public.app_role)));

DROP POLICY IF EXISTS "notification consent own read" ON public.notification_consent_audit;
CREATE POLICY "notification consent own read" ON public.notification_consent_audit
  FOR SELECT TO authenticated
  USING ((user_id = (select auth.uid())) OR (select public.has_role((select auth.uid()),'admin'::public.app_role)));

DROP POLICY IF EXISTS "notification templates admin read" ON public.notification_templates;
CREATE POLICY "notification templates admin read" ON public.notification_templates
  FOR SELECT TO authenticated
  USING ((select public.has_role((select auth.uid()),'admin'::public.app_role)) OR active=true);

DROP POLICY IF EXISTS "notification channels admin read" ON public.notification_channels;
CREATE POLICY "notification channels admin read" ON public.notification_channels
  FOR SELECT TO authenticated
  USING ((select public.has_role((select auth.uid()),'admin'::public.app_role)));

DROP POLICY IF EXISTS "notification flags admin manage" ON public.notification_feature_flags;
CREATE POLICY "notification flags admin manage" ON public.notification_feature_flags
  FOR ALL TO authenticated
  USING ((select public.has_role((select auth.uid()),'admin'::public.app_role)))
  WITH CHECK ((select public.has_role((select auth.uid()),'admin'::public.app_role)));

DROP POLICY IF EXISTS "notification devices own read" ON public.notification_devices;
CREATE POLICY "notification devices own read" ON public.notification_devices
  FOR SELECT TO authenticated
  USING ((user_id = (select auth.uid())) OR (select public.has_role((select auth.uid()),'admin'::public.app_role)));
DROP POLICY IF EXISTS "notification devices own delete" ON public.notification_devices;
CREATE POLICY "notification devices own delete" ON public.notification_devices
  FOR DELETE TO authenticated
  USING ((user_id = (select auth.uid())) OR (select public.has_role((select auth.uid()),'admin'::public.app_role)));

DROP POLICY IF EXISTS "notification provider health admin read" ON public.notification_provider_health;
CREATE POLICY "notification provider health admin read" ON public.notification_provider_health
  FOR SELECT TO authenticated
  USING ((select public.has_role((select auth.uid()),'admin'::public.app_role)));

DROP POLICY IF EXISTS "notification webhook events admin read" ON public.notification_webhook_events;
CREATE POLICY "notification webhook events admin read" ON public.notification_webhook_events
  FOR SELECT TO authenticated
  USING ((select public.has_role((select auth.uid()),'admin'::public.app_role)));

-- Preserve the service-only delivery evidence boundary; no authenticated policy is added.
COMMENT ON TABLE public.notification_deliveries IS
  'Service/provider delivery evidence. RLS is enabled with no client policies intentionally; provider workers and trusted service-role processes access delivery records. Do not add broad authenticated access.';
