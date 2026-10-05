-- Portal clinical continuity, inpatient meal access, and clerking-driven referral/review scheduling.
-- Keeps the existing patient_referrals/appointments workflow and adds typed, traceable follow-up records.

BEGIN;

ALTER TABLE public.patient_referrals
  ADD COLUMN IF NOT EXISTS referral_type text NOT NULL DEFAULT 'specialist',
  ADD COLUMN IF NOT EXISTS source_field text,
  ADD COLUMN IF NOT EXISTS source_text text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.patient_referrals'::regclass
      AND conname='patient_referrals_referral_type_check'
  ) THEN
    ALTER TABLE public.patient_referrals
      ADD CONSTRAINT patient_referrals_referral_type_check
      CHECK (referral_type IN ('specialist','review'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_patient_referrals_type_status_date
  ON public.patient_referrals(referral_type,status,appointment_date);

-- Patient portal clinical record boundary: patients may read only their own longitudinal record.
CREATE OR REPLACE FUNCTION public.get_patient_hub_clinical_snapshot(_patient_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  is_patient boolean := false;
  is_core boolean := false;
  is_lab boolean := false;
  is_pharmacy boolean := false;
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
  is_core := public.has_role(uid,'admin') OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse');
  is_lab := public.has_role(uid,'lab_technician');
  is_pharmacy := public.has_role(uid,'pharmacist');

  IF is_patient THEN
    IF v_owned_patient IS NULL THEN RAISE EXCEPTION 'Patient clinical history access is not permitted'; END IF;
  ELSIF NOT (is_core OR is_lab OR is_pharmacy) THEN
    RAISE EXCEPTION 'Not authorized to access patient clinical history';
  END IF;

  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients p
    WHERE p.id=_patient_id AND coalesce(p.status,'active') <> 'inactive'
  ) THEN
    RAISE EXCEPTION 'Patient not found or inactive';
  END IF;

  RETURN jsonb_build_object(
    'patient', (
      SELECT to_jsonb(p) - 'user_id'
      FROM public.patients p WHERE p.id=_patient_id
    ),
    'vitals', CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.recorded_at DESC)
      FROM (
        SELECT id,recorded_at,systolic,diastolic,pulse_rate,temperature,respiratory_rate,
               oxygen_saturation,weight_kg,height_cm,bmi,priority,notes,encounter_id
        FROM public.vital_signs WHERE patient_id=_patient_id ORDER BY recorded_at DESC LIMIT 100
      ) x
    ),'[]'::jsonb) ELSE '[]'::jsonb END,
    'encounters', CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (
        SELECT id,created_at,status,encounter_type,chief_complaint,symptoms,clerking_notes,
               principal_diagnosis,treatment_plan,follow_up_date,practitioner_id,provider_id,
               admission_id,started_at,completed_at,submitted_at,version_no
        FROM public.encounters WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100
      ) x
    ),'[]'::jsonb) ELSE '[]'::jsonb END,
    'diagnoses', CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (
        SELECT id,encounter_id,diagnosis,icd_code,is_principal,is_provisional,created_at
        FROM public.diagnoses WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 200
      ) x
    ),'[]'::jsonb) ELSE '[]'::jsonb END,
    'labs', CASE WHEN is_patient OR is_core OR is_lab THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.approved_at DESC NULLS LAST,x.created_at DESC)
      FROM (
        SELECT o.id AS lab_order_id,r.id AS result_id,o.created_at,o.test_name,o.test_category,
               o.priority,o.clinical_notes,o.encounter_id,r.status,r.result_data,r.parameter_results,
               r.result,r.interpretation,r.is_abnormal,r.entered_at,r.approved_at,r.numeric_value,
               r.unit,r.reference_low,r.reference_high,r.abnormal_flag
        FROM public.lab_orders o
        JOIN public.lab_results r ON r.lab_order_id=o.id
        WHERE o.patient_id=_patient_id AND o.status='approved' AND r.status='approved'
        ORDER BY r.approved_at DESC NULLS LAST,o.created_at DESC LIMIT 100
      ) x
    ),'[]'::jsonb) ELSE '[]'::jsonb END,
    'imaging', CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.updated_at DESC)
      FROM (
        SELECT id,encounter_id,created_at,updated_at,study_name,modality,body_site,priority,
               clinical_indication,status,report,impression,completed_at,acknowledged_at
        FROM public.imaging_orders
        WHERE patient_id=_patient_id AND status='completed'
          AND (nullif(trim(coalesce(report,'')),'') IS NOT NULL OR nullif(trim(coalesce(impression,'')),'') IS NOT NULL)
        ORDER BY updated_at DESC LIMIT 100
      ) x
    ),'[]'::jsonb) ELSE '[]'::jsonb END,
    'prescriptions', CASE WHEN is_patient OR is_core OR is_pharmacy THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (
        SELECT id,created_at,medication,medication_name,dosage,frequency,duration,route,status,
               encounter_id,prescribed_by,dispensed_at
        FROM public.prescriptions WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100
      ) x
    ),'[]'::jsonb) ELSE '[]'::jsonb END,
    'documents', CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (
        SELECT id,created_at,document_type,file_name,storage_path,mime_type,file_size,notes,uploaded_by
        FROM public.patient_documents WHERE patient_id=_patient_id ORDER BY created_at DESC LIMIT 100
      ) x
    ),'[]'::jsonb) ELSE '[]'::jsonb END,
    'admissions', CASE WHEN is_patient OR is_core THEN coalesce((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.admitted_at DESC)
      FROM (
        SELECT id,admitted_at,discharged_at,ward,bed,diagnosis,status,reason,discharge_summary
        FROM public.admissions WHERE patient_id=_patient_id ORDER BY admitted_at DESC LIMIT 100
      ) x
    ),'[]'::jsonb) ELSE '[]'::jsonb END
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_patient_hub_clinical_snapshot(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_patient_hub_clinical_snapshot(uuid) TO authenticated;

-- Patient meal menu visibility is tied to active inpatient status, not physical presence.
DROP POLICY IF EXISTS meal_menus_authenticated_read ON public.meal_menus;
CREATE POLICY meal_menus_authenticated_read ON public.meal_menus
FOR SELECT TO authenticated
USING (
  status='published'
  AND (
    public.has_role((SELECT auth.uid()),'admin')
    OR public.has_role((SELECT auth.uid()),'canteen')
    OR NOT public.has_role((SELECT auth.uid()),'patient')
    OR EXISTS (
      SELECT 1
      FROM public.patients p
      JOIN public.admissions a ON a.patient_id=p.id
      WHERE (p.user_id=(SELECT auth.uid())
        OR (p.user_id IS NULL AND lower(p.email)=lower((SELECT auth.jwt()->>'email'))))
        AND a.status='admitted'
        AND coalesce(a.discharged_at,now()+interval '1 second') > now()
    )
  )
);

DROP POLICY IF EXISTS meal_menu_items_authenticated_read ON public.meal_menu_items;
CREATE POLICY meal_menu_items_authenticated_read ON public.meal_menu_items
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.meal_menus m
    WHERE m.id=meal_menu_items.menu_id
      AND m.status='published'
      AND (
        public.has_role((SELECT auth.uid()),'admin')
        OR public.has_role((SELECT auth.uid()),'canteen')
        OR NOT public.has_role((SELECT auth.uid()),'patient')
        OR EXISTS (
          SELECT 1
          FROM public.patients p
          JOIN public.admissions a ON a.patient_id=p.id
          WHERE (p.user_id=(SELECT auth.uid())
            OR (p.user_id IS NULL AND lower(p.email)=lower((SELECT auth.jwt()->>'email'))))
            AND a.status='admitted'
            AND coalesce(a.discharged_at,now()+interval '1 second') > now()
        )
      )
  )
);

CREATE OR REPLACE FUNCTION public.sync_encounter_clerking_followups(_encounter_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  uid uuid:=auth.uid();
  e public.encounters%rowtype;
  v_text text;
  v_specialty text;
  v_type text;
  v_date timestamptz;
  v_reason text;
  v_referral uuid;
  v_created integer:=0;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT * INTO e FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'Encounter not found'; END IF;
  IF e.practitioner_id<>uid AND NOT public.has_role(uid,'admin') AND NOT public.has_role(uid,'it_admin') THEN
    RAISE EXCEPTION 'Only the encounter clinician or administrator can sync clerking follow-ups';
  END IF;

  v_text:=coalesce(e.clerking_notes,'')||E'\n'||coalesce(e.treatment_plan,'');
  v_type:=CASE
    WHEN v_text ~* '(booked|scheduled|arranged)[[:space:]]+(for[[:space:]]+)?(a[[:space:]]+)?(review|follow[ -]?up)'
      OR v_text ~* '(review[[:space:]]+visit|follow[ -]?up[[:space:]]+visit)' THEN 'review'
    WHEN v_text ~* '(booked|referred|refer)[[:space:]]+to[[:space:]]+(see[[:space:]]+)?' THEN 'specialist'
    ELSE NULL
  END;
  IF v_type IS NULL THEN
    RETURN jsonb_build_object('created',0,'reason','No specialist/review instruction detected');
  END IF;

  v_specialty:=NULL;
  IF v_type='specialist' THEN
    SELECT nullif(trim(regexp_replace(
      substring(v_text from '(?i)(?:booked|referred|refer)[[:space:]]+to[[:space:]]+(?:see[[:space:]]+)?(?:a|an|the)?[[:space:]]*([^,.;\n]+)'),
      '(?i)\\s+(?:on|for|at|due|because|regarding)\\s+.*$',''
    )),'') INTO v_specialty;
    v_specialty:=nullif(trim(regexp_replace(coalesce(v_specialty,'Physician'),'(?i)^(a|an|the)[[:space:]]+','')),'');
  ELSE
    v_specialty:='Review';
  END IF;

  IF e.follow_up_date IS NOT NULL THEN
    v_date:=e.follow_up_date::timestamptz;
  END IF;

  v_reason:=CASE WHEN v_type='review' THEN 'Review / follow-up visit requested from clerking sheet'
                ELSE 'Specialist review requested from clerking sheet' END;

  SELECT pr.id INTO v_referral
  FROM public.patient_referrals pr
  WHERE pr.encounter_id=e.id AND pr.referral_type=v_type
    AND pr.status NOT IN ('completed','cancelled')
  ORDER BY pr.created_at DESC LIMIT 1;

  IF v_referral IS NULL THEN
    INSERT INTO public.patient_referrals(
      patient_id,encounter_id,referred_by,destination,specialty,reason,urgency,status,
      clinical_summary,appointment_date,facility_id,referral_type,source_field,source_text
    )
    VALUES(
      e.patient_id,e.id,uid,CASE WHEN v_type='review' THEN 'Review Clinic' ELSE 'Specialist Clinic' END,
      v_specialty,v_reason,'routine','requested',
      coalesce(e.treatment_plan,e.principal_diagnosis),v_date,e.facility_id,v_type,
      'clerking_notes',e.clerking_notes
    )
    RETURNING id INTO v_referral;
    v_created:=1;
  ELSE
    UPDATE public.patient_referrals
    SET specialty=coalesce(v_specialty,specialty),
        appointment_date=coalesce(v_date,appointment_date),
        clinical_summary=coalesce(e.treatment_plan,e.principal_diagnosis,clinical_summary),
        source_text=e.clerking_notes,
        updated_at=now()
    WHERE id=v_referral;
  END IF;

  PERFORM public.record_system_audit(
    CASE WHEN v_type='review' THEN 'review_followup_synced' ELSE 'specialist_referral_synced' END,
    'clinical','encounter',e.id,'info',
    jsonb_build_object('patient_id',e.patient_id,'referral_id',v_referral,'referral_type',v_type,'source_field','clerking_notes')
  );

  RETURN jsonb_build_object('created',v_created,'referral_id',v_referral,'referral_type',v_type,'specialty',v_specialty,'appointment_date',v_date);
END;
$function$;

REVOKE ALL ON FUNCTION public.sync_encounter_clerking_followups(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.sync_encounter_clerking_followups(uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.get_pending_specialist_referrals();

CREATE OR REPLACE FUNCTION public.get_pending_specialist_referrals()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $function$
DECLARE uid uuid:=auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'front_desk')
  ) THEN RAISE EXCEPTION 'Specialist referral queue access is not permitted'; END IF;

  RETURN coalesce((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.appointment_date NULLS FIRST,x.referred_at DESC)
    FROM (
      SELECT pr.id AS referral_id,pr.patient_id,
        concat_ws(' ',p.first_name,p.last_name) AS patient_name,
        extract(year from age(current_date,p.date_of_birth))::integer AS age,
        p.phone AS telephone,pr.specialty,pr.destination,pr.reason,pr.clinical_summary,
        pr.appointment_date,pr.created_at AS referred_at,pr.status,pr.referral_type,
        e.principal_diagnosis,
        pr.source_text
      FROM public.patient_referrals pr
      JOIN public.patients p ON p.id=pr.patient_id
      LEFT JOIN public.encounters e ON e.id=pr.encounter_id
      WHERE pr.referral_type='specialist'
        AND pr.status NOT IN ('completed','cancelled','scheduled')
        AND public.current_user_has_facility_access(pr.facility_id)
    ) x
  ),'[]'::jsonb);
END;
$function$;

DROP FUNCTION IF EXISTS public.get_pending_review_appointments();

CREATE OR REPLACE FUNCTION public.get_pending_review_appointments()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $function$
DECLARE uid uuid:=auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'front_desk')
  ) THEN RAISE EXCEPTION 'Review appointment queue access is not permitted'; END IF;

  RETURN coalesce((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.appointment_date NULLS FIRST,x.referred_at DESC)
    FROM (
      SELECT pr.id AS referral_id,pr.patient_id,
        concat_ws(' ',p.first_name,p.last_name) AS patient_name,
        extract(year from age(current_date,p.date_of_birth))::integer AS age,
        p.phone AS telephone,pr.specialty,pr.destination,pr.reason,pr.clinical_summary,
        pr.appointment_date,pr.created_at AS referred_at,pr.status,pr.referral_type,
        e.principal_diagnosis,e.clerking_notes
      FROM public.patient_referrals pr
      JOIN public.patients p ON p.id=pr.patient_id
      LEFT JOIN public.encounters e ON e.id=pr.encounter_id
      WHERE pr.referral_type='review'
        AND pr.status NOT IN ('completed','cancelled','scheduled')
        AND public.current_user_has_facility_access(pr.facility_id)
    ) x
  ),'[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_patient_referral_appointment_date(_referral_id uuid,_appointment_date timestamptz)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_ref public.patient_referrals%rowtype;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'front_desk')
  ) THEN RAISE EXCEPTION 'Referral scheduling is not permitted'; END IF;
  IF _appointment_date IS NULL OR _appointment_date <= now() THEN RAISE EXCEPTION 'Choose a future appointment date and time'; END IF;
  SELECT * INTO v_ref FROM public.patient_referrals WHERE id=_referral_id FOR UPDATE;
  IF v_ref.id IS NULL THEN RAISE EXCEPTION 'Referral not found'; END IF;
  IF v_ref.status NOT IN ('requested','accepted') THEN RAISE EXCEPTION 'Referral is not awaiting scheduling'; END IF;
  IF NOT public.current_user_has_facility_access(v_ref.facility_id) THEN RAISE EXCEPTION 'Referral facility access is not permitted'; END IF;
  UPDATE public.patient_referrals SET appointment_date=_appointment_date,updated_at=now() WHERE id=_referral_id RETURNING * INTO v_ref;
  RETURN jsonb_build_object('referral_id',v_ref.id,'appointment_date',v_ref.appointment_date,'referral_type',v_ref.referral_type);
END;
$function$;

REVOKE ALL ON FUNCTION public.set_patient_referral_appointment_date(uuid,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_patient_referral_appointment_date(uuid,timestamptz) TO authenticated;

DROP FUNCTION IF EXISTS public.schedule_patient_referral_workflow(uuid);

CREATE OR REPLACE FUNCTION public.schedule_patient_referral_workflow(_referral_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_ref public.patient_referrals%rowtype;
  v_appointment_id uuid;
  v_existing uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse') OR public.has_role(uid,'front_desk')
  ) THEN RAISE EXCEPTION 'Referral scheduling is not permitted'; END IF;

  SELECT * INTO v_ref FROM public.patient_referrals WHERE id=_referral_id FOR UPDATE;
  IF v_ref.id IS NULL THEN RAISE EXCEPTION 'Referral not found'; END IF;
  IF v_ref.status NOT IN ('requested','accepted') THEN RAISE EXCEPTION 'Referral is not awaiting scheduling'; END IF;
  IF v_ref.appointment_date IS NULL THEN RAISE EXCEPTION 'An appointment date is required before initiation'; END IF;
  IF v_ref.appointment_date < now() THEN RAISE EXCEPTION 'The appointment date must be in the future'; END IF;
  IF NOT public.current_user_has_facility_access(v_ref.facility_id) THEN RAISE EXCEPTION 'Referral facility access is not permitted'; END IF;

  SELECT a.id INTO v_existing
  FROM public.appointments a
  WHERE a.patient_id=v_ref.patient_id AND a.scheduled_at=v_ref.appointment_date
    AND coalesce(a.department,'')=CASE WHEN v_ref.referral_type='review' THEN 'Review' ELSE coalesce(v_ref.specialty,v_ref.destination,'specialist') END
    AND coalesce(a.reason,'')=CASE WHEN v_ref.referral_type='review' THEN 'Review: '||coalesce(v_ref.reason,'Follow-up review') ELSE coalesce(v_ref.reason,'') END
    AND a.status NOT IN ('cancelled','no_show')
  ORDER BY a.created_at DESC LIMIT 1;

  IF v_existing IS NULL THEN
    SELECT id INTO v_appointment_id FROM public.create_appointment_workflow(
      v_ref.patient_id,v_ref.appointment_date,
      CASE WHEN v_ref.referral_type='review' THEN 'Review' ELSE coalesce(nullif(trim(v_ref.specialty),''),nullif(trim(v_ref.destination),''),'specialist') END,
      CASE WHEN v_ref.referral_type='review' THEN 'Review: '||coalesce(v_ref.reason,'Follow-up review') ELSE v_ref.reason END
    );
  ELSE
    v_appointment_id:=v_existing;
  END IF;

  UPDATE public.patient_referrals SET status='scheduled',updated_at=now() WHERE id=_referral_id;

  INSERT INTO public.notifications(recipient_role,recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata)
  SELECT 'patient'::public.app_role,p.user_id,
    CASE WHEN v_ref.referral_type='review' THEN 'Review appointment scheduled' ELSE 'Specialist appointment scheduled' END,
    concat('Your ',CASE WHEN v_ref.referral_type='review' THEN 'review' ELSE 'specialist' END,' appointment is scheduled for ',to_char(v_ref.appointment_date,'DD Mon YYYY HH24:MI')),
    'info','appointment','/appointments',v_ref.patient_id,v_appointment_id,
    jsonb_build_object('referral_id',v_ref.id,'referral_type',v_ref.referral_type,'appointment_date',v_ref.appointment_date,'specialty',v_ref.specialty)
  FROM public.patients p
  WHERE p.id=v_ref.patient_id AND p.user_id IS NOT NULL;

  PERFORM public.record_system_audit('referral_scheduled','care_transitions','patient_referral',_referral_id,'info',
    jsonb_build_object('patient_id',v_ref.patient_id,'specialty',v_ref.specialty,'referral_type',v_ref.referral_type,'appointment_id',v_appointment_id,'appointment_date',v_ref.appointment_date));

  RETURN jsonb_build_object('referral_id',_referral_id,'status','scheduled','appointment_id',v_appointment_id,'appointment_date',v_ref.appointment_date,'referral_type',v_ref.referral_type);
END;
$function$;

REVOKE ALL ON FUNCTION public.schedule_patient_referral_workflow(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.schedule_patient_referral_workflow(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
