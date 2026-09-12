-- Phase 6: persistent anaesthetic assessment foundation.
-- Safe to apply to an existing database: columns are added only when missing.

CREATE TABLE IF NOT EXISTS public.anesthetic_assessments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  assessed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  asa_class TEXT NOT NULL DEFAULT 'I' CHECK (asa_class IN ('I','II','III','IV','V','VI')),
  airway_assessment TEXT,
  cardiovascular TEXT,
  respiratory TEXT,
  allergies TEXT,
  medications TEXT,
  fasting_status TEXT,
  conclusions TEXT,
  cleared_for_procedure BOOLEAN NOT NULL DEFAULT false,
  cleared_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('draft','completed','superseded')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.anesthetic_assessments ADD COLUMN IF NOT EXISTS assessed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.anesthetic_assessments ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_anesthetic_assessments_patient_time
  ON public.anesthetic_assessments(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_anesthetic_assessments_clearance
  ON public.anesthetic_assessments(patient_id, cleared_for_procedure, created_at DESC);

ALTER TABLE public.anesthetic_assessments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "clinical staff read anesthetic assessments" ON public.anesthetic_assessments;
CREATE POLICY "clinical staff read anesthetic assessments"
  ON public.anesthetic_assessments FOR SELECT TO authenticated
  USING (
    public.is_clinical_staff(auth.uid())
    OR public.has_role(auth.uid(),'specialist_nurse')
    OR public.has_role(auth.uid(),'admin')
  );

DROP POLICY IF EXISTS "clinical staff create anesthetic assessments" ON public.anesthetic_assessments;
CREATE POLICY "clinical staff create anesthetic assessments"
  ON public.anesthetic_assessments FOR INSERT TO authenticated
  WITH CHECK (
    public.is_clinical_staff(auth.uid())
    OR public.has_role(auth.uid(),'specialist_nurse')
    OR public.has_role(auth.uid(),'admin')
  );

DROP POLICY IF EXISTS "admins manage anesthetic assessments" ON public.anesthetic_assessments;
CREATE POLICY "admins manage anesthetic assessments"
  ON public.anesthetic_assessments FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(),'admin'))
  WITH CHECK (public.has_role(auth.uid(),'admin'));

DROP TRIGGER IF EXISTS t_anesthetic_assessments_updated ON public.anesthetic_assessments;
CREATE TRIGGER t_anesthetic_assessments_updated
  BEFORE UPDATE ON public.anesthetic_assessments
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Record the authenticated clinician who creates an assessment when the client omits it.
CREATE OR REPLACE FUNCTION public.set_anesthetic_assessor()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.assessed_by IS NULL THEN
    NEW.assessed_by := auth.uid();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS t_anesthetic_assessor ON public.anesthetic_assessments;
CREATE TRIGGER t_anesthetic_assessor
  BEFORE INSERT ON public.anesthetic_assessments
  FOR EACH ROW EXECUTE FUNCTION public.set_anesthetic_assessor();
