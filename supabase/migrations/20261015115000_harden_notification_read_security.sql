-- Pin notification authorization helpers to a trusted search path.
-- Keep function signatures and existing recipient/facility authorization behavior unchanged.
ALTER FUNCTION public.can_manage_notification(uuid)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.mark_notification_read(uuid)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.mark_notifications_read(uuid[])
  SET search_path = pg_catalog, public;
