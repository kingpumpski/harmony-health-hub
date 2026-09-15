-- Durable interoperability delivery ledger for the next-generation HIMS.
-- Transport state is separate from clinical truth and cannot authorise clinical actions.

CREATE TABLE IF NOT EXISTS public.platform_integration_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id TEXT NOT NULL UNIQUE,
  correlation_id TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('inbound','outbound','bidirectional')),
  standard TEXT NOT NULL CHECK (standard IN ('FHIR_R4','FHIR_R5','HL7_V2','DICOM','ASTM','REST_JSON','SOAP_XML')),
  endpoint_id UUID REFERENCES public.platform_integration_endpoints(id) ON DELETE SET NULL,
  message_type TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  lifecycle_state TEXT NOT NULL DEFAULT 'queued' CHECK (lifecycle_state IN ('queued','processing','delivered','failed','quarantined','replay_pending','replayed')),
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_attempt_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS platform_integration_messages_correlation_idx ON public.platform_integration_messages(correlation_id);
CREATE INDEX IF NOT EXISTS platform_integration_messages_state_idx ON public.platform_integration_messages(lifecycle_state, next_attempt_at);

CREATE TABLE IF NOT EXISTS public.platform_integration_delivery_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES public.platform_integration_messages(id) ON DELETE CASCADE,
  attempt_number INTEGER NOT NULL CHECK (attempt_number > 0),
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  outcome TEXT NOT NULL CHECK (outcome IN ('success','retryable_failure','permanent_failure','quarantined')),
  response_code INTEGER,
  error_code TEXT,
  error_message TEXT,
  UNIQUE(message_id, attempt_number)
);

CREATE INDEX IF NOT EXISTS platform_integration_delivery_attempts_message_idx ON public.platform_integration_delivery_attempts(message_id, attempt_number DESC);

ALTER TABLE public.platform_integration_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_integration_delivery_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service role manages integration messages" ON public.platform_integration_messages;
CREATE POLICY "service role manages integration messages" ON public.platform_integration_messages FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "service role manages integration delivery attempts" ON public.platform_integration_delivery_attempts;
CREATE POLICY "service role manages integration delivery attempts" ON public.platform_integration_delivery_attempts FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMENT ON TABLE public.platform_integration_messages IS 'Durable transport ledger for interoperability delivery. Not a source of clinical truth.';
COMMENT ON TABLE public.platform_integration_delivery_attempts IS 'Delivery attempt history used for retry, quarantine and reconciliation.';
