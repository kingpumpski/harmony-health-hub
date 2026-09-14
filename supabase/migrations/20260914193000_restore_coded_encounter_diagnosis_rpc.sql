-- Restore the coded diagnosis contract used by the Encounters UI.
-- The production database had regressed to the legacy two-argument overload,
-- while the application requires an optional ICD-10/STG catalogue code.

CREATE OR REPLACE FUNCTION public.add_encounter_diagnosis(
  _encounter_id UUID,
  _diagnosis TEXT,
  _icd_code TEXT DEFAULT NULL
)
RETURNS public.diagnoses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result public.diagnoses;
  encounter_status TEXT;
  normalized_code TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Not authorized to add diagnoses';
  END IF;

  SELECT status INTO encounter_status
  FROM public.encounters
  WHERE id = _encounter_id;

  IF encounter_status IS NULL THEN
    RAISE EXCEPTION 'Encounter does not exist';
  END IF;

  IF encounter_status IN ('completed', 'cancelled') THEN
    RAISE EXCEPTION 'Completed or cancelled encounters are read-only';
  END IF;

  IF NULLIF(trim(_diagnosis), '') IS NULL THEN
    RAISE EXCEPTION 'Diagnosis is required';
  END IF;

  normalized_code := NULLIF(upper(trim(_icd_code)), '');

  IF normalized_code IS NOT NULL
     AND NOT EXISTS (
       SELECT 1
       FROM public.icd_codes
       WHERE upper(trim(code)) = normalized_code
     ) THEN
    RAISE EXCEPTION 'Diagnosis code is not in the approved ICD-10/STG catalogue';
  END IF;

  INSERT INTO public.diagnoses (encounter_id, diagnosis, icd_code, is_principal)
  VALUES (_encounter_id, trim(_diagnosis), normalized_code, false)
  RETURNING * INTO result;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.add_encounter_diagnosis(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_encounter_diagnosis(UUID, TEXT, TEXT) TO authenticated;
