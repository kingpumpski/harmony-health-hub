-- Phase 2 follow-up: service-order audit events are append-only and written by triggers.
-- SECURITY DEFINER is required because end users must not receive direct INSERT access to the audit stream.
CREATE OR REPLACE FUNCTION public.service_order_event_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.service_order_events(service_order_id, from_status, to_status, actor_id, reason)
    VALUES (NEW.id, NULL, NEW.status, COALESCE(NEW.created_by, auth.uid()), 'order_created');
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.service_order_events(service_order_id, from_status, to_status, actor_id, reason)
    VALUES (NEW.id, OLD.status, NEW.status, COALESCE(NEW.released_by, auth.uid()), NEW.release_reason);
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.service_order_event_trigger() FROM PUBLIC;

-- No direct mutation policy is intentionally granted on service_order_events.
-- The trigger is the sole write path, while staff receive read access through RLS.
