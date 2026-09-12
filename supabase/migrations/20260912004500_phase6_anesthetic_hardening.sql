-- Phase 6: make anesthetic assessment persistence explicit, auditable and clinically safe.

ALTER TABLE public.anesthetic_assessments
  ADD COLUMN IF NOT EXISTS assessed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

UPDATE public.anesthetic_assessments
SET assessed_by = COALESCE(assessed_by, cleared_by)
WHERE assessed_by IS NULL;

CREATE INDEX IF NOT EXISTS idx_anesthetic_assessments_patient_time
  ON public.anesthetic_assessments(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_anesthetic_assessments_clearance
  ON public.anesthetic_assessments(cleared_for_procedure, created_at DESC);

ALTER TABLE public.anesthetic_assessments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "clinical staff read anesthetic assessments" ON public.anesthetic_assessments;
CREATE POLICY "clinical staff read anesthetic assessments"
  ON public.anesthetic_assessments FOR SELECT TO authenticated
  USING (
    public.is_clinical_staff(auth.uid())
    OR public.has_role(auth.uid(), 'specialist_nurse')
    OR public.has_role(auth.uid(), 'admin')
  );

DROP POLICY IF EXISTS "clinical staff create anesthetic assessments" ON public.anesthetic_assessments;
CREATE POLICY "clinical staff create anesthetic assessments"
  ON public.anesthetic_assessments FOR INSERT TO authenticated
  WITH CHECK (
    assessed_by = auth.uid()
    AND (
      public.is_clinical_staff(auth.uid())
      OR public.has_role(auth.uid(), 'specialist_nurse')
      OR public.has_role(auth.uid(), 'admin')
    )
  );

DROP POLICY IF EXISTS "clinicians update own anesthetic assessments" ON public.anesthetic_assessments;
CREATE POLICY "clinicians update own anesthetic assessments"
  ON public.anesthetic_assessments FOR UPDATE TO authenticated
  USING (assessed_by = auth.uid() OR public.has_role(auth.uid(), 'admin'))
  WITH CHECK (assessed_by = auth.uid() OR public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.set_anesthetic_assessment_actor()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL THEN
    NEW.assessed_by := auth.uid();
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS t_anesthetic_assessment_actor ON public.anesthetic_assessments;
CREATE TRIGGER t_anesthetic_assessment_actor
BEFORE INSERT OR UPDATE ON public.anesthetic_assessments
FOR EACH ROW EXECUTE FUNCTION public.set_anesthetic_assessment_actor();

-- Prevent an application client from asserting clearance on behalf of another actor.
CREATE OR REPLACE FUNCTION public.enforce_anesthetic_clearance_actor()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.cleared_for_procedure IS TRUE THEN
    IF auth.uid() IS NULL THEN
      RAISE EXCEPTION 'Authenticated clinician required for procedural clearance';
    END IF;
    NEW.cleared_by := auth.uid();
  ELSE
    NEW.cleared_by := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS t_anesthetic_clearance_actor ON public.anesthetic_assessments;
CREATE TRIGGER t_anesthetic_clearance_actor
BEFORE INSERT OR UPDATE ON public.anesthetic_assessments
FOR EACH ROW EXECUTE FUNCTION public.enforce_anesthetic_clearance_actor();
