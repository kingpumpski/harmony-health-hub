-- Runtime reconciliation carried forward from the current mainline.
-- This migration keeps the next-generation branch additive while restoring the
-- latest patient self-service and platform-troubleshooting read boundaries.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_patient_portal_identity()
RETURNS TABLE(
  id uuid, patient_code text, first_name text, last_name text, email text,
  date_of_birth date, phone text, facility_id uuid
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text := lower(nullif(trim((auth.jwt() ->> 'email')), ''));
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  RETURN QUERY
  SELECT p.id,p.patient_code,p.first_name,p.last_name,p.email,p.date_of_birth,p.phone,p.facility_id
  FROM public.patients p
  WHERE (p.user_id=v_uid OR (p.user_id IS NULL AND v_email IS NOT NULL AND lower(p.email)=v_email))
    AND coalesce(p.status,'active') <> 'inactive'
  ORDER BY (p.user_id=v_uid) DESC,p.created_at DESC
  LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_patient_appointments(
  _patient_id uuid DEFAULT NULL,
  _limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := greatest(1,least(coalesce(_limit,100),100));
  v_patient uuid;
  v_staff boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  v_staff := public.has_role(v_uid,'admin')
    OR public.has_role(v_uid,'system_superuser')
    OR public.has_role(v_uid,'it_admin')
    OR public.has_role(v_uid,'practitioner')
    OR public.has_role(v_uid,'nurse')
    OR public.has_role(v_uid,'midwife')
    OR public.has_role(v_uid,'specialist_nurse')
    OR public.has_role(v_uid,'radiologist')
    OR public.has_role(v_uid,'radiology_technician')
    OR public.has_role(v_uid,'front_desk');

  IF v_staff THEN
    IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;
    PERFORM public.assert_patient_facility_read_context(_patient_id);
    v_patient := _patient_id;
  ELSE
    SELECT p.id INTO v_patient
    FROM public.patients p
    WHERE p.id=coalesce(_patient_id,p.id)
      AND (p.user_id=v_uid OR (p.user_id IS NULL AND lower(p.email)=lower((auth.jwt()->>'email'))))
      AND coalesce(p.status,'active') <> 'inactive'
    ORDER BY (p.user_id=v_uid) DESC,p.created_at DESC
    LIMIT 1;
    IF v_patient IS NULL THEN RAISE EXCEPTION 'Patient appointment access is not permitted'; END IF;
  END IF;

  RETURN coalesce((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.scheduled_at DESC)
    FROM (
      SELECT a.id,a.patient_id,a.scheduled_at,a.reason,a.status,a.department,
             a.attending_officer_id,a.treatment_status,a.treatment_notes
      FROM public.appointments a
      WHERE a.patient_id=v_patient
      ORDER BY a.scheduled_at DESC
      LIMIT v_limit
    ) x
  ),'[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_patient_hub_clinical_snapshot(_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  uid uuid := auth.uid();
  is_patient boolean := false;
  is_core boolean := false;
  is_lab boolean := false;
  is_pharmacy boolean := false;
  is_it_admin boolean := false;
  is_system_superuser boolean := false;
  v_owned_patient uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  SELECT p.id INTO v_owned_patient
  FROM public.patients p
  WHERE p.id=_patient_id
    AND coalesce(p.status,'active') <> 'inactive'
    AND (p.user_id=uid OR (p.user_id IS NULL AND lower(p.email)=lower((auth.jwt()->>'email'))))
  ORDER BY (p.user_id=uid) DESC,p.created_at DESC
  LIMIT 1;

  is_patient := public.has_role(uid,'patient');
  is_it_admin := public.has_role(uid,'it_admin');
  is_system_superuser := public.has_role(uid,'system_superuser');
  is_core := public.has_role(uid,'admin') OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse');
  is_lab := public.has_role(uid,'lab_technician');
  is_pharmacy := public.has_role(uid,'pharmacist');

  IF is_patient THEN
    IF v_owned_patient IS NULL THEN RAISE EXCEPTION 'Patient clinical history access is not permitted'; END IF;
  ELSIF NOT (is_core OR is_it_admin OR is_system_superuser OR is_lab OR is_pharmacy) THEN
    RAISE EXCEPTION 'Not authorized to access patient clinical history';
  END IF;

  IF NOT is_patient AND NOT public.has_role(uid,'admin')
     AND NOT is_it_admin AND NOT is_system_superuser THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.patients p
      WHERE p.id=_patient_id AND public.current_user_has_facility_access(p.facility_id)
    ) THEN
      RAISE EXCEPTION 'Patient facility access is not permitted';
    END IF;
  END IF;

  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients p
    WHERE p.id=_patient_id AND coalesce(p.status,'active') <> 'inactive'
  ) THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;

  RETURN jsonb_build_object(
    'patient',(SELECT to_jsonb(p)-'user_id' FROM public.patients p WHERE p.id=_patient_id),
    'vitals',CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.recorded_at DESC) FROM (
        SELECT id,recorded_at,systolic,diastolic,pulse_rate,temperature,respiratory_rate,
               oxygen_saturation,weight_kg,height_cm,bmi,priority,notes,encounter_id
        FROM public.vital_signs WHERE patient_id=_patient_id ORDER BY recorded_at DESC LIMIT 100
      ) x),'[]'::jsonb) ELSE '[]'::jsonb END,
    'encounters',CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (
        SELECT id,created_at,status,encounter_type,chief_complaint,symptoms,clerking_notes,
               principal_diagnosis,treatment_plan,follow_up_date,practitioner_id,provider_id,
               admission_id,started_at,completed_at,submitted_at,version_no
        FROM public.encounters WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100
      ) x),'[]'::jsonb) ELSE '[]'::jsonb END,
    'diagnoses',CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (
        SELECT id,encounter_id,diagnosis,icd_code,is_principal,is_provisional,created_at
        FROM public.diagnoses WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 200
      ) x),'[]'::jsonb) ELSE '[]'::jsonb END,
    'labs',CASE WHEN is_patient OR is_core OR is_lab THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.approved_at DESC NULLS LAST,x.created_at DESC) FROM (
        SELECT o.id AS lab_order_id,r.id AS result_id,o.created_at,o.test_name,o.test_category,
               o.priority,o.clinical_notes,o.encounter_id,r.status,r.result_data,r.parameter_results,
               r.result,r.interpretation,r.is_abnormal,r.entered_at,r.approved_at,r.numeric_value,
               r.unit,r.reference_low,r.reference_high,r.abnormal_flag
        FROM public.lab_orders o JOIN public.lab_results r ON r.lab_order_id=o.id
        WHERE o.patient_id=_patient_id AND o.status='approved' AND r.status='approved'
        ORDER BY r.approved_at DESC NULLS LAST,o.created_at DESC LIMIT 100
      ) x),'[]'::jsonb) ELSE '[]'::jsonb END,
    'imaging',CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.updated_at DESC) FROM (
        SELECT id,encounter_id,created_at,updated_at,study_name,modality,body_site,priority,
               clinical_indication,status,report,impression,completed_at,acknowledged_at
        FROM public.imaging_orders
        WHERE patient_id=_patient_id AND status='completed'
          AND (nullif(trim(coalesce(report,'')),'') IS NOT NULL OR nullif(trim(coalesce(impression,'')),'') IS NOT NULL)
        ORDER BY updated_at DESC LIMIT 100
      ) x),'[]'::jsonb) ELSE '[]'::jsonb END,
    'prescriptions',CASE WHEN is_patient OR is_core OR is_pharmacy THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (
        SELECT id,created_at,medication,medication_name,dosage,frequency,duration,route,status,
               encounter_id,prescribed_by,dispensed_at
        FROM public.prescriptions WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100
      ) x),'[]'::jsonb) ELSE '[]'::jsonb END,
    'documents',CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (
        SELECT id,created_at,document_type,file_name,storage_path,mime_type,file_size,notes,uploaded_by
        FROM public.patient_documents WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100
      ) x),'[]'::jsonb) ELSE '[]'::jsonb END,
    'admissions',CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.admitted_at DESC) FROM (
        SELECT id,admitted_at,discharged_at,ward,bed,diagnosis,status,reason,discharge_summary
        FROM public.admissions WHERE patient_id=_patient_id ORDER BY admitted_at DESC LIMIT 100
      ) x),'[]'::jsonb) ELSE '[]'::jsonb END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_patient_portal_identity() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.get_patient_appointments(uuid,integer) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.get_patient_hub_clinical_snapshot(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_portal_identity() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_appointments(uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_hub_clinical_snapshot(uuid) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
