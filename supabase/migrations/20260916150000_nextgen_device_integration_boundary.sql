-- Governed device interoperability intake boundary.
-- Device transports enter the durable interoperability ledger only; they never write
-- canonical clinical results directly. Clinical adapters remain responsible for
-- validation, authorisation, transactionality and result finalisation.

CREATE OR REPLACE FUNCTION public.accept_device_integration_message(
  _device_key TEXT,
  _message_id TEXT,
  _correlation_id TEXT,
  _standard TEXT,
  _event_type TEXT,
  _schema_version TEXT,
  _classification TEXT,
  _payload JSONB,
  _patient_reference TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  device_id UUID;
  endpoint_id UUID;
  message_record_id UUID;
  existing_hash TEXT;
  payload_hash TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NULLIF(trim(_device_key), '') IS NULL
     OR NULLIF(trim(_message_id), '') IS NULL
     OR NULLIF(trim(_correlation_id), '') IS NULL
     OR NULLIF(trim(_event_type), '') IS NULL
     OR NULLIF(trim(_schema_version), '') IS NULL THEN
    RAISE EXCEPTION 'Device message identity fields are required';
  END IF;

  IF _payload IS NULL OR jsonb_typeof(_payload) NOT IN ('object', 'array') THEN
    RAISE EXCEPTION 'Device payload must be a JSON object or array';
  END IF;

  IF _standard NOT IN ('FHIR_R4','FHIR_R5','HL7_V2','DICOM','ASTM','REST_JSON','SOAP_XML') THEN
    RAISE EXCEPTION 'Unsupported interoperability standard';
  END IF;

  IF _classification NOT IN ('clinical','operational','financial','administrative') THEN
    RAISE EXCEPTION 'Unsupported message classification';
  END IF;

  SELECT id INTO device_id
  FROM public.platform_device_registry
  WHERE device_key = trim(_device_key)
    AND lifecycle_state = 'active'
  FOR UPDATE;

  IF device_id IS NULL THEN
    RAISE EXCEPTION 'Device is not active';
  END IF;

  SELECT id INTO endpoint_id
  FROM public.platform_integration_endpoints
  WHERE integration_type = 'device'
    AND enabled = TRUE
    AND standard = _standard
  ORDER BY updated_at DESC
  LIMIT 1;

  payload_hash := encode(digest(convert_to(_payload::text, 'UTF8'), 'sha256'), 'hex');

  SELECT id, payload_hash INTO message_record_id, existing_hash
  FROM public.platform_integration_messages
  WHERE message_id = trim(_message_id)
  FOR UPDATE;

  IF message_record_id IS NOT NULL THEN
    IF existing_hash <> payload_hash THEN
      RAISE EXCEPTION 'Message ID collision with different payload';
    END IF;
    RETURN message_record_id;
  END IF;

  INSERT INTO public.platform_integration_messages (
    message_id,
    correlation_id,
    endpoint_id,
    source_system,
    destination_system,
    direction,
    standard,
    event_type,
    schema_version,
    classification,
    patient_reference,
    payload,
    payload_hash,
    lifecycle_state,
    received_at,
    updated_at
  ) VALUES (
    trim(_message_id),
    trim(_correlation_id),
    endpoint_id,
    'device:' || trim(_device_key),
    'harmony-health-hub',
    'inbound',
    _standard,
    trim(_event_type),
    trim(_schema_version),
    _classification,
    NULLIF(trim(_patient_reference), ''),
    _payload,
    payload_hash,
    'queued',
    now(),
    now()
  ) RETURNING id INTO message_record_id;

  UPDATE public.platform_device_registry
  SET last_message_at = now(),
      updated_at = now()
  WHERE id = device_id;

  RETURN message_record_id;
END;
$$;

REVOKE ALL ON FUNCTION public.accept_device_integration_message(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accept_device_integration_message(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB,TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.accept_device_integration_message(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB,TEXT) TO service_role;

COMMENT ON FUNCTION public.accept_device_integration_message(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,JSONB,TEXT)
IS 'Authenticated transport boundary for active clinical devices. Enqueues only into the interoperability ledger and never mutates canonical clinical results.';
