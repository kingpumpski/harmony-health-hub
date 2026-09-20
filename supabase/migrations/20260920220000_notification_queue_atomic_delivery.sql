-- Atomic notification queue claiming + idempotent delivery.
-- Branch-only migration; deployment remains subject to the normal migration pipeline.

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS source_queue_id uuid;

CREATE UNIQUE INDEX IF NOT EXISTS notifications_source_queue_id_uq
  ON public.notifications(source_queue_id)
  WHERE source_queue_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.claim_notification_queue(_limit integer DEFAULT 25)
RETURNS SETOF public.notification_queue
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(_limit, 25), 1), 100);
BEGIN
  IF current_user <> 'service_role' THEN
    RAISE EXCEPTION 'worker-only function';
  END IF;

  RETURN QUERY
  WITH candidates AS (
    SELECT nq.id
    FROM public.notification_queue nq
    WHERE (nq.status = 'pending' AND nq.next_attempt_at <= now())
       OR (nq.status = 'processing' AND nq.updated_at < now() - interval '10 minutes')
    ORDER BY nq.next_attempt_at, nq.created_at
    FOR UPDATE SKIP LOCKED
    LIMIT v_limit
  )
  UPDATE public.notification_queue nq
  SET status = 'processing', updated_at = now()
  FROM candidates c
  WHERE nq.id = c.id
  RETURNING nq.*;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_notification_queue(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notification_queue(integer) TO service_role;

COMMENT ON FUNCTION public.claim_notification_queue(integer)
IS 'Claims due notification queue rows atomically for the trusted background worker.';
