-- Admin + IT notification/system settings control plane.
-- IT administrators may configure and troubleshoot operational notification settings.
-- Production approval remains administrator-only.

CREATE OR REPLACE FUNCTION public.update_facility_configuration_workflow(
  _configuration_id uuid,
  _changes jsonb
)
RETURNS public.facility_configuration
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_config public.facility_configuration;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)) THEN
    RAISE EXCEPTION 'Administrator or IT administrator role required to update facility configuration';
  END IF;
  IF _changes IS NULL OR jsonb_typeof(_changes) <> 'object' THEN
    RAISE EXCEPTION 'Configuration changes must be a JSON object';
  END IF;

  SELECT * INTO v_config
  FROM public.facility_configuration
  WHERE id=_configuration_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Facility configuration not found'; END IF;

  UPDATE public.facility_configuration
  SET
    facility_name = CASE WHEN _changes ? 'facility_name' THEN NULLIF(pg_catalog.btrim(_changes->>'facility_name'),'') ELSE facility_name END,
    facility_code = CASE WHEN _changes ? 'facility_code' THEN NULLIF(pg_catalog.btrim(_changes->>'facility_code'),'') ELSE facility_code END,
    phone = CASE WHEN _changes ? 'phone' THEN NULLIF(pg_catalog.btrim(_changes->>'phone'),'') ELSE phone END,
    email = CASE WHEN _changes ? 'email' THEN NULLIF(pg_catalog.btrim(_changes->>'email'),'') ELSE email END,
    address = CASE WHEN _changes ? 'address' THEN NULLIF(pg_catalog.btrim(_changes->>'address'),'') ELSE address END,
    country = CASE WHEN _changes ? 'country' THEN NULLIF(pg_catalog.btrim(_changes->>'country'),'') ELSE country END,
    currency = CASE WHEN _changes ? 'currency' THEN NULLIF(pg_catalog.btrim(_changes->>'currency'),'') ELSE currency END,
    timezone = CASE WHEN _changes ? 'timezone' THEN NULLIF(pg_catalog.btrim(_changes->>'timezone'),'') ELSE timezone END,
    routing_mode = CASE WHEN _changes ? 'routing_mode' THEN _changes->>'routing_mode' ELSE routing_mode END,
    appointment_buffer_minutes = CASE WHEN _changes ? 'appointment_buffer_minutes' THEN greatest(0,(_changes->>'appointment_buffer_minutes')::integer) ELSE appointment_buffer_minutes END,
    maintenance_mode = CASE WHEN _changes ? 'maintenance_mode' THEN (_changes->>'maintenance_mode')::boolean ELSE maintenance_mode END,
    allow_treatment_before_deposit = CASE WHEN _changes ? 'allow_treatment_before_deposit' THEN (_changes->>'allow_treatment_before_deposit')::boolean ELSE allow_treatment_before_deposit END,
    admission_financial_override_enabled = CASE WHEN _changes ? 'admission_financial_override_enabled' THEN (_changes->>'admission_financial_override_enabled')::boolean ELSE admission_financial_override_enabled END,
    require_accounts_release_after_deposit = CASE WHEN _changes ? 'require_accounts_release_after_deposit' THEN (_changes->>'require_accounts_release_after_deposit')::boolean ELSE require_accounts_release_after_deposit END,
    allow_clinical_emergency_override = CASE WHEN _changes ? 'allow_clinical_emergency_override' THEN (_changes->>'allow_clinical_emergency_override')::boolean ELSE allow_clinical_emergency_override END,
    require_principal_diagnosis_for_final = CASE WHEN _changes ? 'require_principal_diagnosis_for_final' THEN (_changes->>'require_principal_diagnosis_for_final')::boolean ELSE require_principal_diagnosis_for_final END,
    inherit_inpatient_diagnoses = CASE WHEN _changes ? 'inherit_inpatient_diagnoses' THEN (_changes->>'inherit_inpatient_diagnoses')::boolean ELSE inherit_inpatient_diagnoses END,
    notification_sound_enabled = CASE WHEN _changes ? 'notification_sound_enabled' THEN (_changes->>'notification_sound_enabled')::boolean ELSE notification_sound_enabled END,
    updated_by=uid, updated_at=now()
  WHERE id=_configuration_id
  RETURNING * INTO v_config;

  IF v_config.routing_mode NOT IN ('pay_before_each_step','streamlined') THEN
    RAISE EXCEPTION 'Invalid facility routing mode';
  END IF;

  PERFORM public.record_system_audit(
    'facility_configuration_updated','administration','facility_configuration',v_config.id,'info',
    jsonb_build_object('updated_by',uid,'changed_fields',(SELECT jsonb_agg(key) FROM jsonb_object_keys(_changes) AS key))
  );
  RETURN v_config;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_facility_notification_configuration(
  _facility_id uuid,
  _changes jsonb
)
RETURNS public.facility_notification_config
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_config public.facility_notification_config;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)) THEN
    RAISE EXCEPTION 'Administrator or IT administrator role required to configure notifications';
  END IF;
  IF NOT public.has_facility_access(uid,_facility_id) THEN RAISE EXCEPTION 'Facility access required'; END IF;
  IF _changes IS NULL OR jsonb_typeof(_changes) <> 'object' THEN RAISE EXCEPTION 'Notification configuration must be a JSON object'; END IF;

  INSERT INTO public.facility_notification_config(facility_id,created_by,updated_by)
  VALUES(_facility_id,uid,uid)
  ON CONFLICT(facility_id) DO NOTHING;

  SELECT * INTO v_config FROM public.facility_notification_config
  WHERE facility_id=_facility_id FOR UPDATE;

  UPDATE public.facility_notification_config
  SET
    environment = CASE WHEN _changes ? 'environment' THEN (_changes->>'environment') ELSE environment END,
    enabled = CASE WHEN _changes ? 'enabled' THEN (_changes->>'enabled')::boolean ELSE enabled END,
    default_locale = CASE WHEN _changes ? 'default_locale' THEN COALESCE(NULLIF(pg_catalog.btrim(_changes->>'default_locale'),''),default_locale) ELSE default_locale END,
    default_timezone = CASE WHEN _changes ? 'default_timezone' THEN COALESCE(NULLIF(pg_catalog.btrim(_changes->>'default_timezone'),''),default_timezone) ELSE default_timezone END,
    quiet_hours_start = CASE WHEN _changes ? 'quiet_hours_start' THEN (_changes->>'quiet_hours_start')::time ELSE quiet_hours_start END,
    quiet_hours_end = CASE WHEN _changes ? 'quiet_hours_end' THEN (_changes->>'quiet_hours_end')::time ELSE quiet_hours_end END,
    enabled_channels = CASE WHEN _changes ? 'enabled_channels' THEN (_changes->'enabled_channels') ELSE enabled_channels END,
    branding = CASE WHEN _changes ? 'branding' THEN (_changes->'branding') ELSE branding END,
    provider_defaults = CASE WHEN _changes ? 'provider_defaults' THEN (_changes->'provider_defaults') ELSE provider_defaults END,
    delivery_policy = CASE WHEN _changes ? 'delivery_policy' THEN (_changes->'delivery_policy') ELSE delivery_policy END,
    webhook_policy = CASE WHEN _changes ? 'webhook_policy' THEN (_changes->'webhook_policy') ELSE webhook_policy END,
    compliance_policy = CASE WHEN _changes ? 'compliance_policy' THEN (_changes->'compliance_policy') ELSE compliance_policy END,
    operational_contacts = CASE WHEN _changes ? 'operational_contacts' THEN (_changes->'operational_contacts') ELSE operational_contacts END,
    deployment_secret_namespace = CASE WHEN _changes ? 'deployment_secret_namespace' THEN NULLIF(pg_catalog.btrim(_changes->>'deployment_secret_namespace'),'') ELSE deployment_secret_namespace END,
    rollout_percent = CASE WHEN _changes ? 'rollout_percent' THEN greatest(0,least(100,(_changes->>'rollout_percent')::integer)) ELSE rollout_percent END,
    kill_switch = CASE WHEN _changes ? 'kill_switch' THEN (_changes->>'kill_switch')::boolean ELSE kill_switch END,
    updated_by=uid, updated_at=now()
  WHERE facility_id=_facility_id
  RETURNING * INTO v_config;

  IF v_config.environment NOT IN ('sandbox','test','production') THEN RAISE EXCEPTION 'Invalid notification environment'; END IF;
  IF v_config.default_timezone IS NULL OR pg_catalog.btrim(v_config.default_timezone) = '' THEN RAISE EXCEPTION 'Notification timezone is required'; END IF;

  PERFORM public.record_system_audit(
    'facility_notification_configuration_updated','administration','facility_notification_config',v_config.facility_id,'info',
    jsonb_build_object('updated_by',uid,'changed_fields',(SELECT jsonb_agg(key) FROM jsonb_object_keys(_changes) AS key))
  );
  RETURN v_config;
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_facility_notification_provider(
  _facility_id UUID,
  _channel TEXT,
  _provider TEXT,
  _environment TEXT DEFAULT 'sandbox',
  _secret_reference TEXT DEFAULT NULL,
  _sender_identity TEXT DEFAULT NULL,
  _account_reference TEXT DEFAULT NULL,
  _metadata JSONB DEFAULT '{}'::jsonb
)
RETURNS public.facility_notification_provider_connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.facility_notification_provider_connections;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'it_admin')) OR NOT public.has_facility_access(auth.uid(),_facility_id) THEN
    RAISE EXCEPTION 'Notification provider configuration requires administrator or IT administrator facility access';
  END IF;
  IF _secret_reference IS NOT NULL AND length(_secret_reference) > 255 THEN RAISE EXCEPTION 'Secret reference is too long'; END IF;

  INSERT INTO public.facility_notification_provider_connections(
    facility_id,channel,provider,environment,secret_reference,sender_identity,account_reference,status,metadata,created_by,updated_by
  ) VALUES(
    _facility_id,_channel,_provider,_environment,NULLIF(trim(_secret_reference),''),NULLIF(trim(_sender_identity),''),
    NULLIF(trim(_account_reference),''),CASE WHEN NULLIF(trim(_secret_reference),'') IS NULL THEN 'not_configured' ELSE 'configured' END,
    COALESCE(_metadata,'{}'::jsonb),auth.uid(),auth.uid()
  )
  ON CONFLICT(facility_id,channel,environment) DO UPDATE SET
    provider=EXCLUDED.provider,secret_reference=EXCLUDED.secret_reference,sender_identity=EXCLUDED.sender_identity,
    account_reference=EXCLUDED.account_reference,status=EXCLUDED.status,metadata=EXCLUDED.metadata,
    updated_by=auth.uid(),updated_at=now()
  RETURNING * INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.verify_facility_notification_provider(
  _facility_id UUID,_channel TEXT,_environment TEXT DEFAULT 'sandbox',_verified BOOLEAN DEFAULT true,_error TEXT DEFAULT NULL
)
RETURNS public.facility_notification_provider_connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.facility_notification_provider_connections;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'it_admin')) OR NOT public.has_facility_access(auth.uid(),_facility_id) THEN
    RAISE EXCEPTION 'Notification provider verification requires administrator or IT administrator facility access';
  END IF;
  UPDATE public.facility_notification_provider_connections
  SET status=CASE WHEN _verified THEN 'verified' ELSE 'failed' END,
      last_verified_at=CASE WHEN _verified THEN now() ELSE last_verified_at END,
      last_error=CASE WHEN _verified THEN NULL ELSE NULLIF(left(_error,500),'') END,
      updated_by=auth.uid(),updated_at=now()
  WHERE facility_id=_facility_id AND channel=_channel AND environment=_environment
  RETURNING * INTO v;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Notification provider connection not found'; END IF;
  IF _verified AND v.secret_reference IS NULL THEN RAISE EXCEPTION 'Verified provider requires a deployment secret reference'; END IF;
  IF _verified THEN
    UPDATE public.facility_notification_config
    SET onboarding_status=CASE WHEN environment='production' THEN 'verification_pending' ELSE 'sandbox_ready' END,
        verified_at=now(),verified_by=auth.uid(),updated_by=auth.uid(),updated_at=now()
    WHERE facility_id=_facility_id AND onboarding_status <> 'production_ready';
  END IF;
  RETURN v;
END $$;

REVOKE ALL ON FUNCTION public.update_facility_configuration_workflow(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_facility_configuration_workflow(uuid,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.update_facility_notification_configuration(uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_facility_notification_configuration(uuid,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.set_facility_notification_provider(uuid,text,text,text,text,text,text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_facility_notification_provider(uuid,text,text,text,text,text,text,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.verify_facility_notification_provider(uuid,text,text,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.verify_facility_notification_provider(uuid,text,text,boolean,text) TO authenticated;

-- Production approval is a governance action and remains administrator-only.
REVOKE ALL ON FUNCTION public.mark_facility_notification_production_ready(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.mark_facility_notification_production_ready(uuid) TO authenticated;

COMMENT ON FUNCTION public.update_facility_notification_configuration(uuid,jsonb)
IS 'Server-authorized facility notification configuration. Admin and IT admin may configure; production approval remains admin-only.';
