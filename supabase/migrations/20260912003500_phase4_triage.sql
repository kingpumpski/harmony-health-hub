-- Phase 4: real triage persistence and clinical priority audit.
CREATE TABLE IF NOT EXISTS public.triage_assessments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  recorded_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  systolic INTEGER NOT NULL CHECK (systolic > 0 AND systolic < 400),
  diastolic INTEGER NOT NULL CHECK (diastolic > 0 AND diastolic < 300),
  heart_rate INTEGER NOT NULL CHECK (heart_rate > 0 AND heart_rate < 300),
  temperature NUMERIC(4,1) NOT NULL CHECK (temperature > 20 AND temperature < 50),
  respiratory_rate INTEGER NOT NULL CHECK (respiratory_rate > 0 AND respiratory_rate < 100),
  oxygen_saturation NUMERIC(5,2) NOT NULL CHECK (oxygen_saturation >= 0 AND oxygen_saturation <= 100),
  weight_kg NUMERIC(6,2) CHECK (weight_kg IS NULL OR weight_kg > 0),
  height_m NUMERIC(4,2) CHECK (height_m IS NULL OR height_m > 0),
  pain_score INTEGER CHECK (pain_score IS NULL OR (pain_score BETWEEN 0 AND 10)),
  consciousness TEXT,
  presenting_complaint TEXT,
  clinical_notes TEXT,
  priority TEXT NOT NULL CHECK (priority IN ('critical','urgent','moderate','routine')),
  is_critical BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_triage_patient_time ON public.triage_assessments(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_triage_priority_time ON public.triage_assessments(priority, created_at DESC);

ALTER TABLE public.triage_assessments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "clinical staff read triage" ON public.triage_assessments;
CREATE POLICY "clinical staff read triage" ON public.triage_assessments FOR SELECT TO authenticated
  USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'admin'));

DROP POLICY IF EXISTS "clinical staff create triage" ON public.triage_assessments;
CREATE POLICY "clinical staff create triage" ON public.triage_assessments FOR INSERT TO authenticated
  WITH CHECK ((public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'specialist_nurse')) AND recorded_by = auth.uid());

DROP POLICY IF EXISTS "admins update triage" ON public.triage_assessments;
CREATE POLICY "admins update triage" ON public.triage_assessments FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(),'admin'))
  WITH CHECK (public.has_role(auth.uid(),'admin'));

DROP TRIGGER IF EXISTS t_triage_updated ON public.triage_assessments;
CREATE TRIGGER t_triage_updated BEFORE UPDATE ON public.triage_assessments
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
