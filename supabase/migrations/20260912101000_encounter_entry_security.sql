-- Server-authoritative encounter authoring helpers. Existing audit triggers remain in force.

CREATE OR REPLACE FUNCTION public.create_encounter_workflow(
  _patient_id UUID,
  _symptoms TEXT DEFAULT NULL,
  _clerking_notes TEXT DEFAULT NULL
)
RETURNS public.encounters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE result public.encounters;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'midwife'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)) THEN
    RAISE EXCEPTION 'Only authorized clinical staff may create encounters';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN RAISE EXCEPTION 'Patient does not exist'; END IF;
  INSERT INTO public.encounters (patient_id, symptoms, clerking_notes, practitioner_id, status)
  VALUES (_patient_id, NULLIF(trim(_symptoms), ''), NULLIF(trim(_clerking_notes), ''), auth.uid(), 'draft')
  RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_encounter_diagnosis(_encounter_id UUID, _diagnosis TEXT)
RETURNS public.diagnoses
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result public.diagnoses;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'midwife'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to add diagnoses'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.encounters WHERE id = _encounter_id) THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
  IF NULLIF(trim(_diagnosis), '') IS NULL THEN RAISE EXCEPTION 'Diagnosis is required'; END IF;
  INSERT INTO public.diagnoses (encounter_id, diagnosis, is_principal) VALUES (_encounter_id, trim(_diagnosis), false) RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_principal_diagnosis(_encounter_id UUID, _diagnosis_id UUID)
RETURNS public.diagnoses
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result public.diagnoses;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'midwife'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to set principal diagnosis'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.diagnoses WHERE id = _diagnosis_id AND encounter_id = _encounter_id) THEN RAISE EXCEPTION 'Diagnosis does not belong to encounter'; END IF;
  UPDATE public.diagnoses SET is_principal = false WHERE encounter_id = _encounter_id;
  UPDATE public.diagnoses SET is_principal = true WHERE id = _diagnosis_id RETURNING * INTO result;
  UPDATE public.encounters SET principal_diagnosis = result.diagnosis, updated_at = COALESCE(updated_at, now()) WHERE id = _encounter_id;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_encounter_diagnosis(_diagnosis_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'midwife'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to remove diagnoses'; END IF;
  DELETE FROM public.diagnoses WHERE id = _diagnosis_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_encounter_prescription(
  _encounter_id UUID,
  _medication TEXT,
  _dosage TEXT DEFAULT NULL,
  _frequency TEXT DEFAULT NULL,
  _duration TEXT DEFAULT NULL
)
RETURNS public.prescriptions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result public.prescriptions; patient_id_value UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'midwife'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to prescribe'; END IF;
  SELECT patient_id INTO patient_id_value FROM public.encounters WHERE id = _encounter_id;
  IF patient_id_value IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
  IF NULLIF(trim(_medication), '') IS NULL THEN RAISE EXCEPTION 'Medication is required'; END IF;
  INSERT INTO public.prescriptions (encounter_id, patient_id, prescribed_by, medication, dosage, frequency, duration)
  VALUES (_encounter_id, patient_id_value, auth.uid(), trim(_medication), NULLIF(trim(_dosage), ''), NULLIF(trim(_frequency), ''), NULLIF(trim(_duration), ''))
  RETURNING * INTO result;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_encounter_workflow(_encounter_id UUID)
RETURNS public.encounters
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE result public.encounters;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(), 'admin'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'midwife'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to complete encounters'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.encounters WHERE id = _encounter_id AND principal_diagnosis IS NOT NULL AND NULLIF(trim(principal_diagnosis), '') IS NOT NULL) THEN RAISE EXCEPTION 'Principal diagnosis required'; END IF;
  UPDATE public.encounters SET status = 'completed', completed_at = COALESCE(completed_at, now()), updated_at = COALESCE(updated_at, now()) WHERE id = _encounter_id RETURNING * INTO result;
  IF result.id IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;
  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_encounter_workflow(UUID,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_encounter_diagnosis(UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_principal_diagnosis(UUID,UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_encounter_diagnosis(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_encounter_prescription(UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_encounter_workflow(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_encounter_workflow(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_encounter_diagnosis(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_principal_diagnosis(UUID,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_encounter_diagnosis(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_encounter_prescription(UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_encounter_workflow(UUID) TO authenticated;
