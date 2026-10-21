BEGIN;

DROP POLICY IF EXISTS canteen_operations_broadcast_read ON realtime.messages;
CREATE POLICY canteen_operations_broadcast_read ON realtime.messages
  FOR SELECT TO authenticated
  USING (
    realtime.topic() = 'canteen:operations'
    AND (public.has_role((select auth.uid()),'admin'::public.app_role) OR public.has_role((select auth.uid()),'canteen'::public.app_role))
  );

COMMIT;
