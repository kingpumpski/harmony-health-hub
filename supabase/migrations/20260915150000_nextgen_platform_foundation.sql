-- Next-generation HIMS reference-platform foundation.
-- This migration is intentionally additive and does not replace existing clinical tables.
-- Production promotion requires a separate migration replay and RLS verification gate.

CREATE TABLE IF NOT EXISTS public.platform_deployment_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_key TEXT NOT NULL UNIQUE,
  country_code TEXT NOT NULL,
  region_code TEXT,
  display_name TEXT NOT NULL,
  default_locale TEXT NOT NULL DEFAULT 'en',
  timezone TEXT NOT NULL DEFAULT 'UTC',
  currency_code TEXT NOT NULL DEFAULT 'USD',
  data_residency_region TEXT,
  regulatory_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
  clinical_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
  communication_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
  accessibility_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
  security_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
  enabled_modules JSONB NOT NULL DEFAULT '[]'::jsonb,
  effective_from TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (length(country_code) BETWEEN 2 AND 3),
  CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE TABLE IF NOT EXISTS public.platform_device_registry (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id UUID,
  device_key TEXT NOT NULL UNIQUE,
  device_type TEXT NOT NULL,
  manufacturer TEXT,
  model TEXT,
  serial_number TEXT,
  firmware_version TEXT,
  protocol TEXT NOT NULL,
  endpoint JSONB NOT NULL DEFAULT '{}'::jsonb,
  capabilities JSONB NOT NULL DEFAULT '{}'::jsonb,
  lifecycle_state TEXT NOT NULL DEFAULT 'proposed'
    CHECK (lifecycle_state IN ('proposed','onboarding','validation','active','degraded','quarantined','maintenance','retired')),
  last_heartbeat_at TIMESTAMPTZ,
  last_message_at TIMESTAMPTZ,
  provenance_policy JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.platform_integration_endpoints (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id UUID,
  endpoint_key TEXT NOT NULL UNIQUE,
  integration_type TEXT NOT NULL,
  standard TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('inbound','outbound','bidirectional')),
  configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  health_state TEXT NOT NULL DEFAULT 'unknown'
    CHECK (health_state IN ('unknown','healthy','degraded','failed','disabled')),
  last_success_at TIMESTAMPTZ,
  last_failure_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.platform_event_schemas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_name TEXT NOT NULL,
  version INTEGER NOT NULL,
  domain TEXT NOT NULL,
  classification TEXT NOT NULL DEFAULT 'internal',
  schema JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','approved','deprecated','retired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(event_name, version)
);

CREATE TABLE IF NOT EXISTS public.platform_ai_model_registry (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_key TEXT NOT NULL UNIQUE,
  provider TEXT NOT NULL,
  model_name TEXT NOT NULL,
  model_version TEXT NOT NULL,
  intended_use TEXT NOT NULL,
  prohibited_use TEXT NOT NULL,
  risk_class TEXT NOT NULL,
  lifecycle_state TEXT NOT NULL DEFAULT 'proposed'
    CHECK (lifecycle_state IN ('proposed','validated','approved','active','restricted','suspended','retired')),
  safety_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
  source_policy JSONB NOT NULL DEFAULT '{}'::jsonb,
  data_governance JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.platform_ai_model_evaluations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id UUID NOT NULL REFERENCES public.platform_ai_model_registry(id) ON DELETE CASCADE,
  evaluation_type TEXT NOT NULL,
  evaluation_version TEXT NOT NULL,
  evaluated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  evaluator_id UUID,
  metrics JSONB NOT NULL DEFAULT '{}'::jsonb,
  bias_results JSONB NOT NULL DEFAULT '{}'::jsonb,
  safety_results JSONB NOT NULL DEFAULT '{}'::jsonb,
  decision TEXT NOT NULL CHECK (decision IN ('pass','conditional','fail')),
  evidence_uri TEXT
);

CREATE TABLE IF NOT EXISTS public.user_accessibility_preferences (
  user_id UUID PRIMARY KEY,
  text_scale NUMERIC NOT NULL DEFAULT 1 CHECK (text_scale BETWEEN 0.8 AND 3),
  high_contrast BOOLEAN NOT NULL DEFAULT FALSE,
  reduced_motion BOOLEAN NOT NULL DEFAULT FALSE,
  screen_reader_optimized BOOLEAN NOT NULL DEFAULT FALSE,
  captions_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  read_aloud_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  voice_navigation_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  preferred_language TEXT NOT NULL DEFAULT 'en',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.patient_communication_preferences (
  patient_id UUID PRIMARY KEY,
  preferred_language TEXT NOT NULL DEFAULT 'en',
  preferred_channels JSONB NOT NULL DEFAULT '["in_app"]'::jsonb,
  quiet_hours JSONB NOT NULL DEFAULT '{}'::jsonb,
  appointment_reminders BOOLEAN NOT NULL DEFAULT TRUE,
  medication_reminders BOOLEAN NOT NULL DEFAULT TRUE,
  result_notifications BOOLEAN NOT NULL DEFAULT TRUE,
  marketing_messages BOOLEAN NOT NULL DEFAULT FALSE,
  accessibility_needs JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_by UUID,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.platform_deployment_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_device_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_integration_endpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_event_schemas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_ai_model_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_ai_model_evaluations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_accessibility_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_communication_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "platform deployment service access" ON public.platform_deployment_profiles;
CREATE POLICY "platform deployment service access" ON public.platform_deployment_profiles
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "platform device service access" ON public.platform_device_registry;
CREATE POLICY "platform device service access" ON public.platform_device_registry
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "platform integration service access" ON public.platform_integration_endpoints;
CREATE POLICY "platform integration service access" ON public.platform_integration_endpoints
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "platform event schema service access" ON public.platform_event_schemas;
CREATE POLICY "platform event schema service access" ON public.platform_event_schemas
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "platform AI registry service access" ON public.platform_ai_model_registry;
CREATE POLICY "platform AI registry service access" ON public.platform_ai_model_registry
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "platform AI evaluation service access" ON public.platform_ai_model_evaluations;
CREATE POLICY "platform AI evaluation service access" ON public.platform_ai_model_evaluations
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "users manage own accessibility preferences" ON public.user_accessibility_preferences;
CREATE POLICY "users manage own accessibility preferences" ON public.user_accessibility_preferences
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "patient communication service access" ON public.patient_communication_preferences;
CREATE POLICY "patient communication service access" ON public.patient_communication_preferences
  FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMENT ON TABLE public.platform_deployment_profiles IS 'Versioned jurisdiction/facility deployment configuration for the next-generation HIMS reference architecture.';
COMMENT ON TABLE public.platform_device_registry IS 'Vendor-neutral registry and lifecycle record for laboratory, imaging and other connected clinical equipment.';
COMMENT ON TABLE public.platform_integration_endpoints IS 'Governed HL7/FHIR/DICOM/ASTM and partner integration endpoint configuration.';
COMMENT ON TABLE public.platform_event_schemas IS 'Versioned event contracts for the HIMS event-driven backbone.';
COMMENT ON TABLE public.platform_ai_model_registry IS 'Governed AI model inventory with intended/prohibited use and lifecycle state.';
COMMENT ON TABLE public.platform_ai_model_evaluations IS 'Validation, safety, fairness and release evidence for registered AI models.';
COMMENT ON TABLE public.user_accessibility_preferences IS 'User accessibility preferences used by the experience layer.';
COMMENT ON TABLE public.patient_communication_preferences IS 'Consent-aware patient communication preferences; PHI-bearing content remains outside notification telemetry.';
