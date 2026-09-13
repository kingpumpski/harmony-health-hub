-- Read-only BMI context for authorized clinical decision support.
CREATE OR REPLACE FUNCTION public.get_patient_bmi_context(_patient_id UUID)
RETURNS TABLE(
  bmi NUMERIC,
  category TEXT,
  weight_kg NUMERIC,
  height_m NUMERIC,
  recorded_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin'::public.app_role)
    OR public.has_role(auth.uid(),'practitioner'::public.app_role)
    OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role)
    OR public.has_role(auth.uid(),'pharmacist'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Clinical access required';
  END IF;

  RETURN QUERY
  SELECT t.bmi,
         public.get_bmi_category(t.bmi),
         t.weight_kg,
         t.height_m,
         t.created_at
  FROM public.triage_assessments t
  WHERE t.patient_id = _patient_id
    AND t.bmi IS NOT NULL
  ORDER BY t.created_at DESC
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.get_patient_bmi_context(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_patient_bmi_context(UUID) TO authenticated;
