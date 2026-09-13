-- Transfusion safety reconciliation: consent must be confirmed by the
-- server-side creation contract, not only by the UI.
CREATE OR REPLACE FUNCTION public.create_transfusion_record(
  _patient_id UUID,
  _blood_product TEXT,
  _unit_identifier TEXT,
  _blood_group TEXT DEFAULT NULL,
  _consent_confirmed BOOLEAN DEFAULT FALSE
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid UUID := auth.uid(); v_id UUID;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR
    public.has_role(uid,'practitioner') OR
    public.has_role(uid,'nurse') OR
    public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Clinical role required';
  END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_blood_product),'') IS NULL OR NULLIF(trim(_unit_identifier),'') IS NULL THEN
    RAISE EXCEPTION 'Patient, blood product and unit identifier are required';
  END IF;
  IF COALESCE(_consent_confirmed,FALSE) IS NOT TRUE THEN
    RAISE EXCEPTION 'Documented transfusion consent must be confirmed before scheduling';
  END IF;
  INSERT INTO public.transfusion_records(
    patient_id,blood_product,unit_identifier,blood_group,consent_confirmed,status
  ) VALUES (
    _patient_id,trim(_blood_product),trim(_unit_identifier),NULLIF(trim(_blood_group),''),TRUE,'planned'
  ) RETURNING id INTO v_id;
  PERFORM public.record_system_audit(
    'transfusion_record_created','transfusion','transfusion_record',v_id,'info',
    jsonb_build_object('patient_id',_patient_id,'blood_product',trim(_blood_product),'consent_confirmed',TRUE)
  );
  RETURN v_id;
END; $$;

REVOKE ALL ON FUNCTION public.create_transfusion_record(UUID,TEXT,TEXT,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_transfusion_record(UUID,TEXT,TEXT,TEXT,BOOLEAN) TO authenticated;
