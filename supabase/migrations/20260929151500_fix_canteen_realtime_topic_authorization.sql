BEGIN;

DROP POLICY IF EXISTS canteen_operations_broadcast_read ON realtime.messages;
CREATE POLICY canteen_operations_broadcast_read ON realtime.messages
  FOR SELECT TO authenticated
  USING (
    realtime.topic() = 'canteen:operations'
    AND (public.has_role((SELECT auth.uid()),'admin') OR public.has_role((SELECT auth.uid()),'canteen'))
  );

COMMIT;
