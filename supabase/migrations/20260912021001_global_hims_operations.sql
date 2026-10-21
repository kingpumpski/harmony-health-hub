-- Global HIMS operations foundation: maternity care, facility configuration and system audit.
-- Additive by design; does not replace existing clinical tables.

CREATE TABLE IF NOT EXISTS public.facility_configuration (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_name TEXT NOT NULL DEFAULT 'Harmony Health Hub',
  facility_code TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  country TEXT NOT NULL DEFAULT 'Ghana',
  currency TEXT NOT NULL DEFAULT 'GHS',
  timezone TEXT NOT NULL DEFAULT 'Africa/Accra',
  routing_mode TEXT NOT NULL DEFAULT 'pay_before_each_step' CHECK (routing_mode IN ('pay_before_each_step','streamlined')),
  appointment_buffer_minutes INTEGER NOT NULL DEFAULT 15 CHECK (appointment_buffer_minutes >= 0),
  maintenance_mode BOOLEAN NOT NULL DEFAULT false,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_facility_configuration_singleton ON public.facility_configuration ((true));

INSERT INTO public.facility_configuration (facility_name)
SELECT 'Harmony Health Hub'
WHERE NOT EXISTS (SELECT 1 FROM public.facility_configuration);

CREATE TABLE IF NOT EXISTS public.system_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  module TEXT NOT NULL,
  entity_type TEXT,
  entity_id UUID,
  severity TEXT NOT NULL DEFAULT 'info' CHECK (severity IN ('info','warning','critical')),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_system_audit_log_created_at ON public.system_audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_system_audit_log_actor ON public.system_audit_log(actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_system_audit_log_module ON public.system_audit_log(module, created_at DESC);

CREATE TABLE IF NOT EXISTS public.maternity_episodes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  gravida INTEGER CHECK (gravida IS NULL OR gravida >= 0),
  para INTEGER CHECK (para IS NULL OR para >= 0),
  living_children INTEGER CHECK (living_children IS NULL OR living_children >= 0),
  lmp DATE,
  edd DATE,
  gestational_age_weeks NUMERIC(5,2),
  blood_pressure TEXT,
  fetal_heart_rate INTEGER,
  fundal_height_cm NUMERIC(5,2),
  presentation TEXT,
  risk_level TEXT NOT NULL DEFAULT 'routine' CHECK (risk_level IN ('routine','high','critical')),
  status TEXT NOT NULL DEFAULT 'antenatal' CHECK (status IN ('antenatal','labour','postpartum','completed','cancelled')),
  notes TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.maternity_observations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  episode_id UUID NOT NULL REFERENCES public.maternity_episodes(id) ON DELETE CASCADE,
  observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  blood_pressure TEXT,
  pulse INTEGER,
  temperature NUMERIC(5,2),
  fetal_heart_rate INTEGER,
  contractions_per_10_min INTEGER,
  cervical_dilation_cm NUMERIC(4,1),
  effacement_percent INTEGER,
  station TEXT,
  membrane_status TEXT,
  notes TEXT,
  recorded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_maternity_episodes_patient ON public.maternity_episodes(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_maternity_observations_episode ON public.maternity_observations(episode_id, observed_at DESC);

ALTER TABLE public.facility_configuration ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maternity_episodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maternity_observations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "facility configuration admin manage" ON public.facility_configuration;
CREATE POLICY "facility configuration admin manage" ON public.facility_configuration FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

DROP POLICY IF EXISTS "facility configuration authenticated read" ON public.facility_configuration;
CREATE POLICY "facility configuration authenticated read" ON public.facility_configuration FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "system audit admin read" ON public.system_audit_log;
CREATE POLICY "system audit admin read" ON public.system_audit_log FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin'));

DROP POLICY IF EXISTS "system audit authenticated insert" ON public.system_audit_log;
CREATE POLICY "system audit authenticated insert" ON public.system_audit_log FOR INSERT TO authenticated WITH CHECK (actor_id = auth.uid());

DROP POLICY IF EXISTS "maternity clinical read" ON public.maternity_episodes;
CREATE POLICY "maternity clinical read" ON public.maternity_episodes FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse'));

DROP POLICY IF EXISTS "maternity clinical write" ON public.maternity_episodes;
CREATE POLICY "maternity clinical write" ON public.maternity_episodes FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) WITH CHECK (created_by = auth.uid() OR public.has_role(auth.uid(),'admin'));

DROP POLICY IF EXISTS "maternity observations clinical read" ON public.maternity_observations;
CREATE POLICY "maternity observations clinical read" ON public.maternity_observations FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse'));

DROP POLICY IF EXISTS "maternity observations clinical write" ON public.maternity_observations;
CREATE POLICY "maternity observations clinical write" ON public.maternity_observations FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) WITH CHECK (recorded_by = auth.uid() OR public.has_role(auth.uid(),'admin'));

CREATE OR REPLACE FUNCTION public.touch_global_hims_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS t_facility_configuration_updated_at ON public.facility_configuration;
CREATE TRIGGER t_facility_configuration_updated_at BEFORE UPDATE ON public.facility_configuration FOR EACH ROW EXECUTE FUNCTION public.touch_global_hims_updated_at();
DROP TRIGGER IF EXISTS t_maternity_episode_updated_at ON public.maternity_episodes;
CREATE TRIGGER t_maternity_episode_updated_at BEFORE UPDATE ON public.maternity_episodes FOR EACH ROW EXECUTE FUNCTION public.touch_global_hims_updated_at();

CREATE OR REPLACE FUNCTION public.record_system_audit(_action TEXT, _module TEXT, _entity_type TEXT DEFAULT NULL, _entity_id UUID DEFAULT NULL, _severity TEXT DEFAULT 'info', _metadata JSONB DEFAULT '{}'::jsonb)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  INSERT INTO public.system_audit_log(actor_id, action, module, entity_type, entity_id, severity, metadata)
  VALUES (auth.uid(), _action, _module, _entity_type, _entity_id, _severity, COALESCE(_metadata,'{}'::jsonb))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.record_system_audit(TEXT,TEXT,TEXT,UUID,TEXT,JSONB) TO authenticated;
