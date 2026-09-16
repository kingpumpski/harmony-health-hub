-- Next-generation device lifecycle and heartbeat workflow.
-- Keeps device configuration service-owned while exposing narrow, audited RPC boundaries.
-- Clinical device ingestion must still enter through the governed interoperability delivery path.

CREATE OR REPLACE FUNCTION public.register_platform_device(
  _device_key TEXT,
  _device_type TEXT,
  _protocol TEXT,
  _manufacturer TEXT DEFAULT NULL,
  _model TEXT DEFAULT NULL,
  _serial_number TEXT DEFAULT NULL,
  _firmware_version TEXT DEFAULT NULL,
  _endpoint JSONB DEFAULT '{}'::jsonb,
  _capabilities JSONB DEFAULT '{}'::jsonb,
  _facility_id UUID DEFAULT NULL
)
RETURNS public.platform_device_registry
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.platform_device_registry;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Only administrators may register platform devices';
  END IF;
  IF NULLIF(trim(_device_key), '') IS NULL THEN
    RAISE EXCEPTION 'Device key is required';
  END IF;
  IF NULLIF(trim(_device_type), '') IS NULL THEN
    RAISE EXCEPTION 'Device type is required';
  END IF;
  IF NULLIF(trim(_protocol), '') IS NULL THEN
    RAISE EXCEPTION 'Device protocol is required';
  END IF;
  IF jsonb_typeof(COALESCE(_endpoint, '{}'::jsonb)) <> 'object' THEN
    RAISE EXCEPTION 'Device endpoint configuration must be a JSON object';
  END IF;
  IF jsonb_typeof(COALESCE(_capabilities, '{}'::jsonb)) <> 'object' THEN
    RAISE EXCEPTION 'Device capabilities must be a JSON object';
  END IF;

  INSERT INTO public.platform_device_registry (
    facility_id,
    device_key,
    device_type,
    manufacturer,
    model,
    serial_number,
    firmware_version,
    protocol,
    endpoint,
    capabilities,
    lifecycle_state,
    created_by
  )
  VALUES (
    _facility_id,
    trim(_device_key),
    trim(_device_type),
    NULLIF(trim(_manufacturer), ''),
    NULLIF(trim(_model), ''),
    NULLIF(trim(_serial_number), ''),
    NULLIF(trim(_firmware_version), ''),
    upper(trim(_protocol)),
    COALESCE(_endpoint, '{}'::jsonb),
    COALESCE(_capabilities, '{}'::jsonb),
    'onboarding',
    auth.uid()
  )
  RETURNING * INTO result;

  RETURN result;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'A platform device with this device key already exists';
END;
$$;

CREATE OR REPLACE FUNCTION public.transition_platform_device(
  _device_id UUID,
  _target_state TEXT,
  _reason TEXT DEFAULT NULL
)
RETURNS public.platform_device_registry
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_state TEXT;
  result public.platform_device_registry;
  normalized_target TEXT := lower(trim(_target_state));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Only administrators may transition platform devices';
  END IF;
  IF _device_id IS NULL OR normalized_target IS NULL OR normalized_target = '' THEN
    RAISE EXCEPTION 'Device and target lifecycle state are required';
  END IF;
  IF NULLIF(trim(_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A lifecycle transition reason is required';
  END IF;

  SELECT lifecycle_state INTO current_state
  FROM public.platform_device_registry
  WHERE id = _device_id
  FOR UPDATE;

  IF current_state IS NULL THEN
    RAISE EXCEPTION 'Platform device not found';
  END IF;

  IF NOT (
    (current_state = 'proposed' AND normalized_target IN ('onboarding','retired')) OR
    (current_state = 'onboarding' AND normalized_target IN ('validation','maintenance','quarantined','retired')) OR
    (current_state = 'validation' AND normalized_target IN ('active','quarantined','maintenance','retired')) OR
    (current_state = 'active' AND normalized_target IN ('degraded','quarantined','maintenance','retired')) OR
    (current_state = 'degraded' AND normalized_target IN ('active','quarantined','maintenance','retired')) OR
    (current_state = 'quarantined' AND normalized_target IN ('validation','maintenance','retired')) OR
    (current_state = 'maintenance' AND normalized_target IN ('validation','active','quarantined','retired'))
  ) THEN
    RAISE EXCEPTION 'Invalid platform device lifecycle transition: % -> %', current_state, normalized_target;
  END IF;

  UPDATE public.platform_device_registry
  SET lifecycle_state = normalized_target,
      updated_at = now()
  WHERE id = _device_id
  RETURNING * INTO result;

  PERFORM public.record_system_audit(
    'platform_device_lifecycle_transition',
    'integration',
    'platform_device_registry',
    _device_id,
    CASE WHEN normalized_target IN ('quarantined','retired') THEN 'warning' ELSE 'info' END,
    jsonb_build_object(
      'device_id', _device_id,
      'from_state', current_state,
      'to_state', normalized_target,
      'reason', trim(_reason),
      'actor_id', auth.uid()
    )
  );

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_platform_device_heartbeat(
  _device_key TEXT,
  _message_at TIMESTAMPTZ DEFAULT now()
)
RETURNS public.platform_device_registry
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.platform_device_registry;
BEGIN
  IF NULLIF(trim(_device_key), '') IS NULL THEN
    RAISE EXCEPTION 'Device key is required';
  END IF;
  IF _message_at IS NULL OR _message_at > now() + interval '5 minutes' THEN
    RAISE EXCEPTION 'Invalid device heartbeat timestamp';
  END IF;

  UPDATE public.platform_device_registry
  SET last_heartbeat_at = now(),
      last_message_at = _message_at,
      updated_at = now()
  WHERE device_key = trim(_device_key)
    AND lifecycle_state NOT IN ('retired','quarantined')
  RETURNING * INTO result;

  IF result.id IS NULL THEN
    RAISE EXCEPTION 'Device not found or not permitted to report heartbeat';
  END IF;

  RETURN result;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_platform_device_registry_changes ON public.platform_device_registry;
CREATE TRIGGER trg_audit_platform_device_registry_changes
AFTER INSERT OR UPDATE OR DELETE ON public.platform_device_registry
FOR EACH ROW EXECUTE FUNCTION public.audit_clinical_record_change();

REVOKE INSERT, UPDATE, DELETE ON public.platform_device_registry FROM authenticated;
REVOKE ALL ON FUNCTION public.register_platform_device(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.transition_platform_device(UUID, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_platform_device_heartbeat(TEXT, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_platform_device(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, JSONB, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_platform_device(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_platform_device_heartbeat(TEXT, TIMESTAMPTZ) TO service_role;

COMMENT ON FUNCTION public.register_platform_device IS 'Admin-only audited onboarding boundary for connected clinical and operational devices.';
COMMENT ON FUNCTION public.transition_platform_device IS 'Admin-only state machine for governed device lifecycle transitions.';
COMMENT ON FUNCTION public.record_platform_device_heartbeat IS 'Service-role heartbeat boundary; quarantined and retired devices cannot report as healthy.';
