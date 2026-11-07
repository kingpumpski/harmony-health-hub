-- The production notification control plane contains a service-only
-- delivery evidence table. Recreate its canonical contract before the advisor
-- migration adds indexes/comments and the internal-table RLS migration denies
-- Data API access.
CREATE TABLE IF NOT EXISTS public.notification_deliveries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_id UUID NOT NULL REFERENCES public.notification_queue(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  channel TEXT NOT NULL,
  provider TEXT,
  destination_hash TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  provider_message_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at TIMESTAMPTZ,
  UNIQUE (queue_id, user_id, channel)
);

CREATE INDEX IF NOT EXISTS notification_deliveries_status_idx
  ON public.notification_deliveries(status, updated_at DESC);

ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS trg_notification_deliveries_touch
  ON public.notification_deliveries;
CREATE TRIGGER trg_notification_deliveries_touch
  BEFORE UPDATE ON public.notification_deliveries
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

REVOKE ALL ON TABLE public.notification_deliveries FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.notification_deliveries TO service_role;
