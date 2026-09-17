-- Facility administrator controls for admission/emergency financial routing.
-- facility_configuration is the canonical configuration surface used by the admin UI.
ALTER TABLE public.facility_configuration
  ADD COLUMN IF NOT EXISTS allow_treatment_before_deposit BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS admission_financial_override_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS require_accounts_release_after_deposit BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS allow_clinical_emergency_override BOOLEAN NOT NULL DEFAULT TRUE;

CREATE OR REPLACE FUNCTION public.admit_encounter_workflow(
  _encounter_id UUID,
  _reason TEXT DEFAULT NULL,
  _ward TEXT DEFAULT NULL,
  _emergency_override BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_enc public.encounters%ROWTYPE;
  v_admission UUID;
  v_override BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN
    RAISE EXCEPTION 'Admission is not permitted for this role';
  END IF;
  SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
  IF v_enc.id IS NULL THEN RAISE EXCEPTION 'Encounter not found'; END IF;
  IF v_enc.status <> 'completed' THEN RAISE EXCEPTION 'Submit the encounter before admission'; END IF;
  IF v_enc.admission_id IS NOT NULL THEN
    RETURN jsonb_build_object('admission_id',v_enc.admission_id,'override',FALSE,'existing',TRUE);
  END IF;
  SELECT allow_treatment_before_deposit AND admission_financial_override_enabled AND allow_clinical_emergency_override
    INTO v_override FROM public.facility_configuration LIMIT 1;
  v_override := COALESCE(v_override,FALSE) AND COALESCE(_emergency_override,TRUE);

  INSERT INTO public.admissions(patient_id,encounter_id,ward,reason,admitted_by,status)
  VALUES(v_enc.patient_id,v_enc.id,NULLIF(btrim(_ward),''),COALESCE(NULLIF(btrim(_reason),''),'Clinical admission'),auth.uid(),'admitted')
  RETURNING id INTO v_admission;
  UPDATE public.encounters SET admission_id=v_admission, updated_at=now() WHERE id=v_enc.id;

  IF v_override THEN
    UPDATE public.service_orders
    SET status='released', approved_by=auth.uid(), approved_at=now(), updated_at=now(),
        notes=concat_ws(E'\n',notes,'Emergency admission financial override: treatment released before deposit.')
    WHERE encounter_id=v_enc.id AND status IN ('pending_payment','pending_payment_approval');
    PERFORM public.record_system_audit('admission_financial_override','admissions','admission',v_admission,'critical',jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'override',TRUE));
  END IF;
  PERFORM public.record_system_audit('patient_admitted','admissions','admission',v_admission,'info',jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'financial_override',v_override));
  RETURN jsonb_build_object('admission_id',v_admission,'override',v_override,'status','admitted');
END; $$;
REVOKE ALL ON FUNCTION public.admit_encounter_workflow(UUID,TEXT,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admit_encounter_workflow(UUID,TEXT,TEXT,BOOLEAN) TO authenticated;
