BEGIN;

ALTER FUNCTION public.has_role(uuid, public.app_role)
  SET search_path = pg_catalog, public;

DROP POLICY IF EXISTS meal_menus_authenticated_read ON public.meal_menus;
CREATE POLICY meal_menus_authenticated_read ON public.meal_menus
  FOR SELECT TO authenticated
  USING (
    status = 'published'
    OR public.current_user_has_role('admin'::public.app_role)
    OR public.current_user_has_role('canteen'::public.app_role)
  );

DROP POLICY IF EXISTS meal_menu_items_authenticated_read ON public.meal_menu_items;
CREATE POLICY meal_menu_items_authenticated_read ON public.meal_menu_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.meal_menus m
      WHERE m.id = menu_id
        AND (
          m.status = 'published'
          OR public.current_user_has_role('admin'::public.app_role)
          OR public.current_user_has_role('canteen'::public.app_role)
        )
    )
  );

DROP POLICY IF EXISTS canteen_operations_broadcast_read ON realtime.messages;
CREATE POLICY canteen_operations_broadcast_read ON realtime.messages
  FOR SELECT TO authenticated
  USING (
    realtime.topic() = 'canteen:operations'
    AND (
      public.current_user_has_role('admin'::public.app_role)
      OR public.current_user_has_role('canteen'::public.app_role)
    )
  );

COMMIT;
