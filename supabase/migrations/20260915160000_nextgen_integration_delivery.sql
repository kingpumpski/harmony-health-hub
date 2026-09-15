-- Durable interoperability delivery ledger for the next-generation reference platform.
-- This does not apply clinical effects itself; adapters must enforce domain authorization,
-- idempotency and transactional application before changing canonical clinical data.

CREATE TABLE IF NOT EXISTS public.platform_integration_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id TEXT NOT NULL UNIQUE,
  correlation_id TEXT NOT NULL,
  endpoint_id UUID REFERENCES public.platform_integration_endpoints(id) ON DELETE SET NULL,
  source_system TEXT NOT NULL,
  destination_system TEXT,
  standard TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('inbound','outbound','bidirectional')),
  event_type TEXT NOT NULL,
  schema_version TEXT NOT NULL,
  classification TEXT NOT NULL CHECK (classification IN ('clinical','operational','financial','administrative')),
  patient_reference TEXT,
  payload JSONB NOT NULL,
  delivery_state TEXT NOT NULL DEFAULT 'received'
    CHECK (delivery_state IN ('received','validated','processed','quarantined','replayed','failed')),
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_attempt_at TIMESTAMPTZ,
  last_error_code TEXT,
  last_error_message TEXT,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.platform_integration_delivery_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES public.platform_integration_messages(id) ON DELETE CASCADE,
  attempt_number INTEGER NOT NULL CHECK (attempt_number > 0),
  state TEXT NOT NULL CHECK (state IN ('received','validated','processed','quarantined','replayed','failed')),
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  error_code TEXT,
  error_message TEXT,
  UNIQUE(message_id, attempt_number)
);

CREATE INDEX IF NOT EXISTS idx_platform_integration_messages_delivery
  ON public.platform_integration_messages(delivery_state, next_attempt_at);
CREATE INDEX IF NOT EXISTS idx_platform_integration_messages_correlation
  ON public.platform_integration_messages(correlation_id);
CREATE INDEX IF NOT EXISTS idx_platform_integration_messages_received
  ON public.platform_integration_messages(received_at);
CREATE INDEX IF NOT EXISTS idx_platform_integration_attempts_message
  ON public.platform_integration_delivery_attempts(message_id, attempt_number DESC);

ALTER TABLE public.platform_integration_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_integration_delivery_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform integration messages service access" ON public.platform_integration_messages;
CREATE POLICY "platform integration messages service access" ON public.platform_integration_messages
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "platform integration attempts service access" ON public.platform_integration_delivery_attempts;
CREATE POLICY "platform integration attempts service access" ON public.platform_integration_delivery_attempts
  FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMENT ON TABLE public.platform_integration_messages IS 'Durable idempotent message ledger for governed interoperability adapters; never a substitute for canonical clinical transactions.';
COMMENT ON TABLE public.platform_integration_delivery_attempts IS 'Immutable delivery-attempt history supporting retry, quarantine, replay and operational reconciliation.';
