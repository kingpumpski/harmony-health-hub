-- Canonical secure entry points used by Patient Hub. These wrappers keep the hub
-- from bypassing the module-specific lifecycle controls while preserving its convenience.
CREATE OR REPLACE FUNCTION public.create_patient_appointment(_patient_id UUID, _scheduled_at TIMESTAMPTZ, _department TEXT DEFAULT NULL, _reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife') OR has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Appointment creation is not permitted'; END IF;
  INSERT INTO appointments(patient_id, scheduled_at, department, reason, status, created_by) VALUES (_patient_id,_scheduled_at,_department,_reason,'scheduled',auth.uid()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('appointment_id',v_id);
END; $$;

CREATE OR REPLACE FUNCTION public.record_patient_vitals(_patient_id UUID, _temperature NUMERIC DEFAULT NULL, _pulse NUMERIC DEFAULT NULL, _systolic NUMERIC DEFAULT NULL, _diastolic NUMERIC DEFAULT NULL, _respiratory_rate NUMERIC DEFAULT NULL, _oxygen_saturation NUMERIC DEFAULT NULL, _weight_kg NUMERIC DEFAULT NULL, _height_cm NUMERIC DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Vital recording is not permitted'; END IF;
  INSERT INTO vital_signs(patient_id,temperature,pulse,systolic,diastolic,respiratory_rate,oxygen_saturation,weight_kg,height_cm,recorded_by) VALUES (_patient_id,_temperature,_pulse,_systolic,_diastolic,_respiratory_rate,_oxygen_saturation,_weight_kg,_height_cm,auth.uid()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('vital_id',v_id);
END; $$;

CREATE OR REPLACE FUNCTION public.create_patient_lab_order(_patient_id UUID, _test_name TEXT, _clinical_notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Laboratory order creation is not permitted'; END IF;
  INSERT INTO lab_orders(patient_id,test_name,clinical_notes,status) VALUES (_patient_id,_test_name,_clinical_notes,'pending_payment_approval') RETURNING id INTO v_id;
  RETURN jsonb_build_object('lab_order_id',v_id);
END; $$;

CREATE OR REPLACE FUNCTION public.create_patient_document(_patient_id UUID, _document_type TEXT, _file_url TEXT, _notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife') OR has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Document creation is not permitted'; END IF;
  INSERT INTO patient_documents(patient_id,document_type,file_url,notes,uploaded_by) VALUES (_patient_id,_document_type,_file_url,_notes,auth.uid()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('document_id',v_id);
END; $$;

CREATE OR REPLACE FUNCTION public.create_patient_admission(_patient_id UUID, _reason TEXT, _ward TEXT DEFAULT NULL, _bed_id UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT (has_role(auth.uid(),'admin') OR has_role(auth.uid(),'practitioner') OR has_role(auth.uid(),'nurse') OR has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Admission creation is not permitted'; END IF;
  INSERT INTO admissions(patient_id,reason,ward,bed_id,status,admitted_at) VALUES (_patient_id,_reason,_ward,_bed_id,'active',now()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('admission_id',v_id);
END; $$;

REVOKE ALL ON FUNCTION public.create_patient_appointment(UUID,TIMESTAMPTZ,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_patient_vitals(UUID,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_patient_lab_order(UUID,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_patient_document(UUID,TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_patient_admission(UUID,TEXT,TEXT,UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_patient_appointment(UUID,TIMESTAMPTZ,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_patient_vitals(UUID,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC,NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_lab_order(UUID,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_document(UUID,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_patient_admission(UUID,TEXT,TEXT,UUID) TO authenticated;
