-- Reconcile Patient Hub convenience RPCs with the legacy schema that remains canonical.
-- This migration intentionally corrects column names without reopening direct client writes.

CREATE OR REPLACE FUNCTION public.create_patient_appointment(_patient_id UUID, _scheduled_at TIMESTAMPTZ, _department TEXT DEFAULT NULL, _reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife') OR has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Appointment creation is not permitted'; END IF;
  INSERT INTO appointments(patient_id, scheduled_at, department, reason, status) VALUES (_patient_id,_scheduled_at,_department,_reason,'scheduled') RETURNING id INTO v_id;
  RETURN jsonb_build_object('appointment_id',v_id);
END; $$;

CREATE OR REPLACE FUNCTION public.record_patient_vitals(_patient_id UUID, _temperature NUMERIC DEFAULT NULL, _pulse NUMERIC DEFAULT NULL, _systolic NUMERIC DEFAULT NULL, _diastolic NUMERIC DEFAULT NULL, _respiratory_rate NUMERIC DEFAULT NULL, _oxygen_saturation NUMERIC DEFAULT NULL, _weight_kg NUMERIC DEFAULT NULL, _height_cm NUMERIC DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Vital recording is not permitted'; END IF;
  INSERT INTO vital_signs(patient_id,temperature,pulse_rate,systolic,diastolic,respiratory_rate,oxygen_saturation,weight_kg,height_cm,recorded_by) VALUES (_patient_id,_temperature,_pulse,_systolic,_diastolic,_respiratory_rate,_oxygen_saturation,_weight_kg,_height_cm,auth.uid()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('vital_id',v_id);
END; $$;

CREATE OR REPLACE FUNCTION public.create_patient_lab_order(_patient_id UUID, _test_name TEXT, _clinical_notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Laboratory order creation is not permitted'; END IF;
  INSERT INTO lab_orders(patient_id,test_name,clinical_notes,status,ordered_by) VALUES (_patient_id,_test_name,_clinical_notes,'ordered',auth.uid()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('lab_order_id',v_id);
END; $$;

CREATE OR REPLACE FUNCTION public.create_patient_prescription(_patient_id UUID, _medication TEXT, _dosage TEXT, _frequency TEXT, _duration TEXT DEFAULT NULL, _instructions TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Prescription creation is not permitted'; END IF;
  INSERT INTO prescriptions(patient_id,prescribed_by,medication,dosage,frequency,duration,instructions,status) VALUES (_patient_id,auth.uid(),_medication,_dosage,_frequency,_duration,_instructions,'pending') RETURNING id INTO v_id;
  RETURN jsonb_build_object('prescription_id',v_id);
END; $$;

CREATE OR REPLACE FUNCTION public.create_patient_admission(_patient_id UUID, _reason TEXT, _ward TEXT DEFAULT NULL, _bed TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Admission creation is not permitted'; END IF;
  INSERT INTO admissions(patient_id,ward,bed,reason,admitted_by,status) VALUES (_patient_id,_ward,_bed,_reason,auth.uid(),'admitted') RETURNING id INTO v_id;
  RETURN jsonb_build_object('admission_id',v_id);
END; $$;

GRANT EXECUTE ON FUNCTION public.create_patient_appointment(UUID,TIMESTAMPTZ,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_patient_vitals(UUID,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_lab_order(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_prescription(UUID,TEXT,TEXT,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_admission(UUID,TEXT,TEXT,TEXT) TO authenticated;
