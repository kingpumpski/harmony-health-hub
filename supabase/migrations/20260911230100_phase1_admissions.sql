-- Phase 1 patient hub support: admissions are first-class patient records.
CREATE TABLE IF NOT EXISTS public.admissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  admitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  discharged_at TIMESTAMPTZ,
  ward TEXT,
  bed TEXT,
  admitting_practitioner UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  diagnosis TEXT,
  status TEXT NOT NULL DEFAULT 'admitted' CHECK (status IN ('admitted','discharged','transferred')),
  notes TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admissions_patient_time
  ON public.admissions(patient_id, admitted_at DESC);

ALTER TABLE public.admissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "patients read own admissions" ON public.admissions;
CREATE POLICY "patients read own admissions"
  ON public.admissions FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid()));

DROP POLICY IF EXISTS "staff manage admissions" ON public.admissions;
CREATE POLICY "staff manage admissions"
  ON public.admissions FOR ALL
  USING (public.is_clinical_staff(auth.uid()))
  WITH CHECK (public.is_clinical_staff(auth.uid()));

DROP TRIGGER IF EXISTS t_admissions_updated ON public.admissions;
CREATE TRIGGER t_admissions_updated
BEFORE UPDATE ON public.admissions
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
