-- Harden the historical SECURITY DEFINER helper without changing its API or grants.
ALTER FUNCTION public.enqueue_notification(jsonb, text)
  SET search_path = pg_catalog, public;
