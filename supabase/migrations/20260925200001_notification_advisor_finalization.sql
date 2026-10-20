-- Final notification advisor reconciliation: remove overlapping facility SELECT policies and pin trigger search_path.
CREATE OR REPLACE FUNCTION public.prevent_notification_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $function$
BEGIN
  IF TG_OP = 'DELETE' AND current_setting('notification.audit_erasure', true) = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'Notification audit is immutable';
END;
$function$;

DROP POLICY IF EXISTS "facility notification config access" ON public.facility_notification_config;
DROP POLICY IF EXISTS "facility notification config admin manage" ON public.facility_notification_config;
CREATE POLICY "facility notification config access" ON public.facility_notification_config
  FOR SELECT TO authenticated
  USING ((select public.has_facility_access((select auth.uid()),facility_id)));
CREATE POLICY "facility notification config admin insert" ON public.facility_notification_config
  FOR INSERT TO authenticated
  WITH CHECK (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))));
CREATE POLICY "facility notification config admin update" ON public.facility_notification_config
  FOR UPDATE TO authenticated
  USING (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))))
  WITH CHECK (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))));
CREATE POLICY "facility notification config admin delete" ON public.facility_notification_config
  FOR DELETE TO authenticated
  USING (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))));

DROP POLICY IF EXISTS "facility notification provider access" ON public.facility_notification_provider_connections;
DROP POLICY IF EXISTS "facility notification provider admin manage" ON public.facility_notification_provider_connections;
CREATE POLICY "facility notification provider access" ON public.facility_notification_provider_connections
  FOR SELECT TO authenticated
  USING (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))));
CREATE POLICY "facility notification provider admin insert" ON public.facility_notification_provider_connections
  FOR INSERT TO authenticated
  WITH CHECK (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))));
CREATE POLICY "facility notification provider admin update" ON public.facility_notification_provider_connections
  FOR UPDATE TO authenticated
  USING (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))))
  WITH CHECK (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))));
CREATE POLICY "facility notification provider admin delete" ON public.facility_notification_provider_connections
  FOR DELETE TO authenticated
  USING (((select public.has_facility_access((select auth.uid()),facility_id)))
    AND ((select public.has_role((select auth.uid()),'admin'::public.app_role))
      OR (select public.has_role((select auth.uid()),'it_admin'::public.app_role))));