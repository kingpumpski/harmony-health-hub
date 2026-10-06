BEGIN;

-- Patient self-service must not depend on staff active-facility context.
CREATE OR REPLACE FUNCTION public.patient_has_active_admission()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT EXISTS (
  SELECT 1 FROM public.patients p JOIN public.admissions a ON a.patient_id=p.id
  WHERE (p.user_id=auth.uid() OR (p.user_id IS NULL AND lower(p.email)=lower(auth.jwt()->>'email')))
    AND coalesce(p.status,'active')<>'inactive' AND a.status='admitted'
    AND coalesce(a.discharged_at,now()+interval '1 second')>now()
); $$;
REVOKE ALL ON FUNCTION public.patient_has_active_admission() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.patient_has_active_admission() TO authenticated;

CREATE OR REPLACE FUNCTION public.patient_can_read_meal_menus()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $ SELECT public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'canteen')
  OR NOT public.has_role(auth.uid(),'patient') OR public.patient_has_active_admission(); $;
REVOKE ALL ON FUNCTION public.patient_can_read_meal_menus() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.patient_can_read_meal_menus() TO authenticated;

DROP POLICY IF EXISTS meal_menus_authenticated_read ON public.meal_menus;
CREATE POLICY meal_menus_authenticated_read ON public.meal_menus FOR SELECT TO authenticated
USING (status='published' AND public.patient_can_read_meal_menus());
DROP POLICY IF EXISTS meal_menu_items_authenticated_read ON public.meal_menu_items;
CREATE POLICY meal_menu_items_authenticated_read ON public.meal_menu_items FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.meal_menus m WHERE m.id=meal_menu_items.menu_id AND m.status='published'
  AND public.patient_can_read_meal_menus()));

CREATE OR REPLACE FUNCTION public.create_patient_appointment(_patient_id uuid,_scheduled_at timestamptz,_department text DEFAULT NULL,_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE uid uuid:=auth.uid(); p public.patients%rowtype; v_id uuid; is_patient boolean:=false; owned boolean:=false;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 is_patient:=public.has_role(uid,'patient');
 SELECT * INTO p FROM public.patients WHERE id=_patient_id AND coalesce(status,'active')<>'inactive'
   AND ((is_patient AND (user_id=uid OR (user_id IS NULL AND lower(email)=lower(auth.jwt()->>'email')))) OR NOT is_patient) LIMIT 1;
 IF p.id IS NULL THEN RAISE EXCEPTION 'Patient appointment access is not permitted'; END IF;
 owned:=(p.user_id=uid OR (p.user_id IS NULL AND lower(p.email)=lower(auth.jwt()->>'email')));
 IF is_patient AND NOT owned THEN RAISE EXCEPTION 'You may only request appointments for your own patient record'; END IF;
 IF NOT is_patient AND NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'front_desk')
   OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Appointment creation denied'; END IF;
 IF _scheduled_at IS NULL OR _scheduled_at<=now() THEN RAISE EXCEPTION 'A future appointment time is required'; END IF;
 IF p.facility_id IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
 IF NOT is_patient AND public.current_user_facility_id() IS DISTINCT FROM p.facility_id THEN RAISE EXCEPTION 'Patient belongs to a different facility context. Switch to the patient facility and try again'; END IF;
 INSERT INTO public.appointments(patient_id,practitioner_id,department,scheduled_at,duration_minutes,reason,status,notes,created_at,updated_at,treatment_status,facility_id)
 VALUES(_patient_id,CASE WHEN public.has_role(uid,'practitioner') THEN uid ELSE NULL END,coalesce(nullif(trim(_department),''),'Clinical Consultation'),
   _scheduled_at,30,nullif(trim(_reason),''),'scheduled',CASE WHEN is_patient THEN 'Requested through patient portal' ELSE NULL END,now(),now(),'scheduled',p.facility_id)
 RETURNING id INTO v_id;
 RETURN jsonb_build_object('appointment_id',v_id,'facility_id',p.facility_id);
END; $$;
REVOKE ALL ON FUNCTION public.create_patient_appointment(uuid,timestamptz,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_patient_appointment(uuid,timestamptz,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_ai_report_request(_patient_id uuid,_report_type text DEFAULT 'medical_summary')
RETURNS public.ai_report_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE uid uuid:=auth.uid(); r public.ai_report_requests; typ text:=lower(trim(coalesce(_report_type,'medical_summary'))); email text:=lower(nullif(trim(auth.jwt()->>'email'),''));
 owned boolean;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.patients p WHERE p.id=_patient_id AND coalesce(p.status,'active')<>'inactive'
   AND (p.user_id=uid OR (p.user_id IS NULL AND email IS NOT NULL AND lower(p.email)=email))) INTO owned;
 IF NOT (owned OR public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner')
   OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'radiologist'))
 THEN RAISE EXCEPTION 'Not authorised to request this patient report'; END IF;
 IF typ<>'medical_summary' THEN RAISE EXCEPTION 'Unsupported report type'; END IF;
 INSERT INTO public.ai_report_requests(patient_id,requested_by,report_type,status) VALUES(_patient_id,uid,typ,'processing') RETURNING * INTO r; RETURN r;
END; $$;

CREATE OR REPLACE FUNCTION public.get_ai_report_requests(_patient_id uuid DEFAULT NULL,_limit integer DEFAULT 25)
RETURNS TABLE(id uuid,patient_id uuid,report_type text,requested_by uuid,status text,content text,error text,created_at timestamptz,completed_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE uid uuid:=auth.uid(); email text:=lower(nullif(trim(auth.jwt()->>'email'),''));
 owned boolean; lim integer;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.patients p WHERE p.id=_patient_id AND (p.user_id=uid OR (p.user_id IS NULL AND email IS NOT NULL AND lower(p.email)=email))) INTO owned;
 IF NOT (owned OR public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner')
   OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'radiologist')) THEN RAISE EXCEPTION 'Not authorised'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.patients p WHERE p.id=_patient_id AND coalesce(p.status,'active')<>'inactive') THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
 lim:=least(greatest(coalesce(_limit,25),1),50);
 RETURN QUERY SELECT r.id,r.patient_id,r.report_type,r.requested_by,r.status,r.content,r.error,r.created_at,r.completed_at FROM public.ai_report_requests r WHERE r.patient_id=_patient_id ORDER BY r.created_at DESC LIMIT lim;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_ai_report_request(_request_id uuid,_content text DEFAULT NULL,_error text DEFAULT NULL)
RETURNS public.ai_report_requests LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE uid uuid:=auth.uid(); r public.ai_report_requests; content_text text:=nullif(trim(coalesce(_content,'')),''); error_text text:=nullif(trim(coalesce(_error,'')),''); owned boolean:=false;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT * INTO r FROM public.ai_report_requests WHERE id=_request_id FOR UPDATE; IF r.id IS NULL THEN RAISE EXCEPTION 'Report request not found'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.patients p WHERE p.id=r.patient_id AND (p.user_id=uid OR (p.user_id IS NULL AND lower(p.email)=lower(auth.jwt()->>'email')))) INTO owned;
 IF NOT (r.requested_by=uid OR owned OR public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'radiologist')) THEN RAISE EXCEPTION 'Not authorised to complete this patient report'; END IF;
 IF r.status<>'processing' THEN IF r.status IN('completed','failed') THEN RETURN r; END IF; RAISE EXCEPTION 'Report request is not processing'; END IF;
 IF content_text IS NULL AND error_text IS NULL THEN RAISE EXCEPTION 'Report content or error is required'; END IF;
 UPDATE public.ai_report_requests SET status=CASE WHEN content_text IS NOT NULL THEN 'completed' ELSE 'failed' END,content=CASE WHEN content_text IS NOT NULL THEN content_text END,error=CASE WHEN content_text IS NULL THEN error_text END,completed_at=now() WHERE id=_request_id RETURNING * INTO r; RETURN r;
END; $$;

CREATE OR REPLACE FUNCTION public.get_patient_portal_medical_record(_patient_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE uid uuid:=auth.uid(); email text:=lower(nullif(trim(auth.jwt()->>'email'),''));
 owned boolean;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.patients p WHERE p.id=_patient_id AND coalesce(p.status,'active')<>'inactive'
   AND (p.user_id=uid OR (p.user_id IS NULL AND email IS NOT NULL AND lower(p.email)=email))) INTO owned;
 IF NOT owned THEN RAISE EXCEPTION 'Patient medical record access is not permitted'; END IF;
 RETURN jsonb_build_object(
  'patient',(SELECT jsonb_build_object('id',id,'patient_code',patient_code,'first_name',first_name,'last_name',last_name,'date_of_birth',date_of_birth,'phone',phone,'email',email) FROM public.patients WHERE id=_patient_id),
  'visits',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.completed_at DESC NULLS LAST,x.created_at DESC) FROM (SELECT id,created_at,completed_at,encounter_type,chief_complaint,principal_diagnosis,treatment_plan,follow_up_date,status FROM public.encounters WHERE patient_id=_patient_id AND status='completed' ORDER BY completed_at DESC NULLS LAST,created_at DESC LIMIT 100)x),'[]'::jsonb),
  'confirmed_diagnoses',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT id,encounter_id,diagnosis,icd_code,is_principal,created_at FROM public.diagnoses WHERE patient_id=_patient_id AND coalesce(is_provisional,false)=false ORDER BY created_at DESC LIMIT 200)x),'[]'::jsonb),
  'treatments',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.completed_at DESC NULLS LAST,x.created_at DESC) FROM (SELECT id,completed_at,created_at,encounter_type,principal_diagnosis,treatment_plan,follow_up_date FROM public.encounters WHERE patient_id=_patient_id AND status='completed' AND nullif(trim(coalesce(treatment_plan,'')),'') IS NOT NULL ORDER BY completed_at DESC NULLS LAST,created_at DESC LIMIT 100)x),'[]'::jsonb),
  'vitals',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.recorded_at DESC) FROM (SELECT id,recorded_at,systolic,diastolic,pulse_rate,temperature,respiratory_rate,oxygen_saturation,weight_kg,height_cm,bmi FROM public.vital_signs WHERE patient_id=_patient_id ORDER BY recorded_at DESC LIMIT 100)x),'[]'::jsonb),
  'laboratory_results',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.approved_at DESC NULLS LAST,x.created_at DESC) FROM (SELECT o.id lab_order_id,r.id result_id,o.created_at,o.test_name,o.test_category,r.status,r.result,r.interpretation,r.is_abnormal,r.approved_at,r.numeric_value,r.unit,r.reference_low,r.reference_high,r.abnormal_flag FROM public.lab_orders o JOIN public.lab_results r ON r.lab_order_id=o.id WHERE o.patient_id=_patient_id AND o.status='approved' AND r.status='approved' ORDER BY r.approved_at DESC NULLS LAST,o.created_at DESC LIMIT 100)x),'[]'::jsonb),
  'imaging_results',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.updated_at DESC) FROM (SELECT id,created_at,updated_at,study_name,modality,body_site,clinical_indication,report,impression,completed_at FROM public.imaging_orders WHERE patient_id=_patient_id AND status='completed' AND (nullif(trim(coalesce(report,'')),'') IS NOT NULL OR nullif(trim(coalesce(impression,'')),'') IS NOT NULL) ORDER BY updated_at DESC LIMIT 100)x),'[]'::jsonb),
  'medications',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (SELECT id,created_at,medication_name,medication,dosage,frequency,duration,route,status,dispensed_at FROM public.prescriptions WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100)x),'[]'::jsonb),
  'admissions',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.admitted_at DESC) FROM (SELECT id,admitted_at,discharged_at,ward,bed,diagnosis,status,reason,discharge_summary FROM public.admissions WHERE patient_id=_patient_id ORDER BY admitted_at DESC LIMIT 100)x),'[]'::jsonb)
 );
END; $$;
REVOKE ALL ON FUNCTION public.get_patient_portal_medical_record(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_portal_medical_record(uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.get_patient_telemedicine_clinicians_legacy();
DROP FUNCTION IF EXISTS public.get_patient_telemedicine_clinicians();
CREATE OR REPLACE FUNCTION public.get_patient_telemedicine_clinicians(_scheduled_at timestamptz DEFAULT NULL)
RETURNS TABLE(id uuid,first_name text,last_name text,department text,specialization text,clinician_role text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE uid uuid:=auth.uid(); facility uuid; at_time timestamptz:=coalesce(_scheduled_at,now()+interval '1 day');
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF; IF NOT public.has_role(uid,'patient') THEN RAISE EXCEPTION 'Patient telemedicine access is not permitted'; END IF;
 SELECT p.facility_id INTO facility FROM public.patients p WHERE (p.user_id=uid OR (p.user_id IS NULL AND lower(p.email)=lower(auth.jwt()->>'email'))) AND coalesce(p.status,'active')<>'inactive' ORDER BY (p.user_id=uid) DESC,p.created_at DESC LIMIT 1;
 IF facility IS NULL THEN RAISE EXCEPTION 'Patient facility is not configured'; END IF; IF at_time<=now() THEN RAISE EXCEPTION 'Choose a future date and time'; END IF;
 RETURN QUERY SELECT p.id,p.first_name,p.last_name,p.department,p.specialization,ur.role::text FROM public.profiles p JOIN public.user_roles ur ON ur.user_id=p.id JOIN public.facility_memberships fm ON fm.user_id=p.id AND fm.is_active=true AND fm.facility_id=facility
 WHERE ur.role IN ('practitioner'::public.app_role,'radiologist'::public.app_role)
 AND EXISTS(SELECT 1 FROM public.staff_shift_assignments s WHERE s.user_id=p.id AND s.active=true AND s.starts_at<=at_time AND s.ends_at>at_time)
 GROUP BY p.id,p.first_name,p.last_name,p.department,p.specialization,ur.role ORDER BY p.last_name,p.first_name;
END; $$;
REVOKE ALL ON FUNCTION public.get_patient_telemedicine_clinicians(timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_telemedicine_clinicians(timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.request_patient_telemedicine_session(_clinician_id uuid,_scheduled_at timestamptz,_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE uid uuid:=auth.uid(); patient_id uuid; facility uuid; session_id uuid;
BEGIN
 IF uid IS NULL OR NOT public.has_role(uid,'patient') THEN RAISE EXCEPTION 'Patient telemedicine access is not permitted'; END IF;
 SELECT p.id,p.facility_id INTO patient_id,facility FROM public.patients p WHERE (p.user_id=uid OR (p.user_id IS NULL AND lower(p.email)=lower(auth.jwt()->>'email'))) AND coalesce(p.status,'active')<>'inactive' ORDER BY (p.user_id=uid) DESC,p.created_at DESC LIMIT 1;
 IF patient_id IS NULL OR facility IS NULL THEN RAISE EXCEPTION 'Patient profile or facility is not configured'; END IF; IF _scheduled_at IS NULL OR _scheduled_at<=now() THEN RAISE EXCEPTION 'Choose a future date and time'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.profiles p JOIN public.user_roles ur ON ur.user_id=p.id JOIN public.facility_memberships fm ON fm.user_id=p.id AND fm.is_active=true AND fm.facility_id=facility WHERE p.id=_clinician_id AND ur.role IN ('practitioner'::public.app_role,'radiologist'::public.app_role) AND EXISTS(SELECT 1 FROM public.staff_shift_assignments s WHERE s.user_id=p.id AND s.active=true AND s.starts_at<=_scheduled_at AND s.ends_at>_scheduled_at)) THEN RAISE EXCEPTION 'Selected clinician is not on duty at the requested time'; END IF;
 INSERT INTO public.video_sessions(patient_id,practitioner_id,room_name,provider,scheduled_at,status,payment_required,payment_received,notes,facility_id) VALUES(patient_id,_clinician_id,'pending-'||replace(gen_random_uuid()::text,'-',''),'jitsi',_scheduled_at,'pending_approval',false,false,nullif(trim(_reason),''),facility) RETURNING id INTO session_id;
 RETURN session_id;
END; $$;
REVOKE ALL ON FUNCTION public.request_patient_telemedicine_session(uuid,timestamptz,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.request_patient_telemedicine_session(uuid,timestamptz,text) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;