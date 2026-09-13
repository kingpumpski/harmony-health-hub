-- Ophthalmology production workflow foundation.
-- Stores clinician-recorded measurements; AI remains advisory and is never fabricated
-- from hard-coded findings.

CREATE TABLE IF NOT EXISTS public.ophthalmology_exams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  visual_acuity TEXT,
  refraction TEXT,
  keratometry TEXT,
  intraocular_pressure NUMERIC(6,2) CHECK (intraocular_pressure IS NULL OR intraocular_pressure >= 0),
  color_vision TEXT,
  fundus_notes TEXT,
  image_path TEXT,
  ai_advisory JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('draft','completed','reviewed')),
  performed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ophthalmology_exams_patient ON public.ophthalmology_exams(patient_id, created_at DESC);
ALTER TABLE public.ophthalmology_exams ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ophthalmology clinical read" ON public.ophthalmology_exams;
CREATE POLICY "ophthalmology clinical read" ON public.ophthalmology_exams FOR SELECT TO authenticated USING (
  public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'ophthalmologist') OR public.has_role(auth.uid(),'specialist_nurse')
);

CREATE OR REPLACE FUNCTION public.create_ophthalmology_exam(
  _patient_id UUID,
  _visual_acuity TEXT,
  _refraction TEXT,
  _keratometry TEXT,
  _intraocular_pressure NUMERIC,
  _color_vision TEXT,
  _fundus_notes TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'ophthalmologist')) THEN
    RAISE EXCEPTION 'Ophthalmology clinical role required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF _intraocular_pressure IS NOT NULL AND _intraocular_pressure < 0 THEN RAISE EXCEPTION 'Intraocular pressure cannot be negative'; END IF;

  INSERT INTO public.ophthalmology_exams(patient_id, visual_acuity, refraction, keratometry, intraocular_pressure, color_vision, fundus_notes, performed_by)
  VALUES (_patient_id, NULLIF(trim(_visual_acuity),''), NULLIF(trim(_refraction),''), NULLIF(trim(_keratometry),''), _intraocular_pressure, NULLIF(trim(_color_vision),''), NULLIF(trim(_fundus_notes),''), auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_ophthalmology_exam(_exam_id UUID, _advisory JSONB DEFAULT '{}'::jsonb)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'ophthalmologist')) THEN RAISE EXCEPTION 'Clinical review role required'; END IF;
  UPDATE public.ophthalmology_exams
  SET status='reviewed', reviewed_by=auth.uid(), reviewed_at=now(), ai_advisory=COALESCE(_advisory,'{}'::jsonb), updated_at=now()
  WHERE id=_exam_id;
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.create_ophthalmology_exam(UUID,TEXT,TEXT,TEXT,NUMERIC,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.review_ophthalmology_exam(UUID,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_ophthalmology_exam(UUID,TEXT,TEXT,TEXT,NUMERIC,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_ophthalmology_exam(UUID,JSONB) TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.ophthalmology_exams FROM authenticated;
GRANT SELECT ON public.ophthalmology_exams TO authenticated;
