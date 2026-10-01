-- Prevent clinical RPCs and lineage triggers from silently assigning unresolved legacy
-- patient records to the caller's facility. Legacy attribution must go through the
-- administrator/IT administrator evidence-based reconciliation workflow.

CREATE OR REPLACE FUNCTION public.ensure_encounter_facility_attribution(_encounter_id uuid)
RETURNS public.encounters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog, public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_enc public.encounters;
  v_patient_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Not authorized to establish encounter facility context';
  END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before continuing clinical documentation'; END IF;

  SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
  IF v_enc.id IS NULL THEN RAISE EXCEPTION 'Encounter does not exist'; END IF;

  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p
  WHERE p.id=v_enc.patient_id
  FOR UPDATE;

  IF v_patient_facility IS NULL THEN
    RAISE EXCEPTION 'Patient facility attribution is unresolved; reconcile the patient before clinical documentation';
  END IF;

  IF v_patient_facility<>v_facility THEN
    RAISE EXCEPTION 'Patient belongs to a different facility context';
  END IF;

  IF v_enc.facility_id IS NOT NULL AND v_enc.facility_id<>v_facility THEN
    RAISE EXCEPTION 'Encounter belongs to a different facility context';
  END IF;

  IF v_enc.facility_id IS NULL THEN
    UPDATE public.encounters
    SET facility_id=v_patient_facility,updated_at=pg_catalog.now()
    WHERE id=v_enc.id
    RETURNING * INTO v_enc;
  END IF;

  RETURN v_enc;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_encounter_workflow(_patient_id uuid, _symptoms text DEFAULT NULL::text, _clerking_notes text DEFAULT NULL::text)
RETURNS public.encounters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog, public'
AS $function$
DECLARE
  result public.encounters;
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_admission_id uuid;
  v_initial_encounter_id uuid;
  v_inherit boolean := true;
  v_patient_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'practitioner'::public.app_role) OR public.has_role(uid,'nurse'::public.app_role)
    OR public.has_role(uid,'midwife'::public.app_role) OR public.has_role(uid,'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Only authorized clinical staff may create encounters';
  END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before creating an encounter'; END IF;

  SELECT facility_id INTO v_patient_facility
  FROM public.patients
  WHERE id=_patient_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Patient does not exist'; END IF;
  IF v_patient_facility IS NULL THEN
    RAISE EXCEPTION 'Patient facility attribution is unresolved; reconcile the patient before creating an encounter';
  END IF;
  IF v_patient_facility<>v_facility THEN
    RAISE EXCEPTION 'Patient belongs to a different facility context';
  END IF;

  SELECT id,coalesce(inherit_inpatient_diagnoses,true) INTO v_admission_id,v_inherit
  FROM public.admissions a
  CROSS JOIN LATERAL (
    SELECT coalesce(fc.inherit_inpatient_diagnoses,true) inherit_inpatient_diagnoses
    FROM public.facility_configuration fc
    ORDER BY fc.created_at ASC
    LIMIT 1
  ) cfg
  WHERE a.patient_id=_patient_id
    AND a.status='admitted'
    AND (a.facility_id IS NULL OR a.facility_id=v_facility)
  ORDER BY a.admitted_at ASC NULLS FIRST,a.created_at ASC
  LIMIT 1;

  INSERT INTO public.encounters(
    patient_id,facility_id,symptoms,clerking_notes,practitioner_id,status,admission_id
  )
  VALUES(
    _patient_id,v_facility,nullif(pg_catalog.btrim(_symptoms),''),nullif(pg_catalog.btrim(_clerking_notes),''),
    uid,'draft',v_admission_id
  )
  RETURNING * INTO result;

  IF v_admission_id IS NOT NULL AND v_inherit THEN
    SELECT e.id INTO v_initial_encounter_id
    FROM public.encounters e
    WHERE e.admission_id=v_admission_id
      AND e.id<>result.id
      AND (e.facility_id IS NULL OR e.facility_id=v_facility)
    ORDER BY e.created_at ASC,e.id ASC
    LIMIT 1;

    IF v_initial_encounter_id IS NOT NULL THEN
      INSERT INTO public.diagnoses(encounter_id,diagnosis,is_principal,icd_code,ai_suggested)
      SELECT result.id,d.diagnosis,d.is_principal,d.icd_code,d.ai_suggested
      FROM public.diagnoses d
      WHERE d.encounter_id=v_initial_encounter_id;

      SELECT d.diagnosis INTO result.principal_diagnosis
      FROM public.diagnoses d
      WHERE d.encounter_id=result.id AND d.is_principal=true
      ORDER BY d.created_at ASC,d.id ASC
      LIMIT 1;

      UPDATE public.encounters
      SET principal_diagnosis=result.principal_diagnosis,updated_at=pg_catalog.now()
      WHERE id=result.id
      RETURNING * INTO result;

      PERFORM public.record_system_audit(
        'encounter_diagnoses_inherited','clinical','encounter',result.id,'info',
        jsonb_build_object(
          'patient_id',result.patient_id,'admission_id',v_admission_id,
          'source_encounter_id',v_initial_encounter_id,'facility_id',v_facility
        )
      );
    END IF;
  END IF;

  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.start_appointment_encounter(_appointment_id uuid, _symptoms text DEFAULT NULL::text, _clerking_notes text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_appt public.appointments;
  v_patient_facility uuid;
  v_encounter public.encounters;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(v_user, 'admin'::public.app_role)
    OR public.has_role(v_user, 'practitioner'::public.app_role)
    OR public.has_role(v_user, 'nurse'::public.app_role)
    OR public.has_role(v_user, 'midwife'::public.app_role)
    OR public.has_role(v_user, 'specialist_nurse'::public.app_role)
  ) THEN RAISE EXCEPTION 'Clinical access required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'An active facility is required before starting an appointment encounter'; END IF;

  SELECT * INTO v_appt FROM public.appointments WHERE id = _appointment_id FOR UPDATE;
  IF v_appt.id IS NULL THEN RAISE EXCEPTION 'Appointment not found'; END IF;

  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p
  WHERE p.id = v_appt.patient_id
  FOR UPDATE;

  IF v_patient_facility IS NULL THEN
    RAISE EXCEPTION 'Patient facility attribution is unresolved; reconcile the patient before starting the appointment';
  END IF;
  IF v_patient_facility IS DISTINCT FROM v_facility THEN
    RAISE EXCEPTION 'Patient belongs to a different facility context';
  END IF;

  IF v_appt.facility_id IS NULL THEN
    UPDATE public.appointments
    SET facility_id = v_facility, updated_at = pg_catalog.now()
    WHERE id = v_appt.id AND facility_id IS NULL;
    SELECT * INTO v_appt FROM public.appointments WHERE id = _appointment_id FOR UPDATE;
  END IF;

  IF v_appt.facility_id IS DISTINCT FROM v_facility THEN
    RAISE EXCEPTION 'Appointment belongs to a different facility context';
  END IF;
  IF v_appt.treatment_status IN ('completed', 'cancelled', 'no_show') THEN
    RAISE EXCEPTION 'Appointment is not available for treatment';
  END IF;
  IF v_appt.attending_officer_id IS NOT NULL AND v_appt.attending_officer_id <> v_user THEN
    RAISE EXCEPTION 'Appointment is assigned to another officer';
  END IF;

  UPDATE public.appointments
  SET attending_officer_id = v_user,
      claimed_at = COALESCE(claimed_at, pg_catalog.now()),
      treatment_status = 'in_progress',
      started_at = COALESCE(started_at, pg_catalog.now()),
      updated_at = pg_catalog.now()
  WHERE id = _appointment_id;

  SELECT e.* INTO v_encounter
  FROM public.encounters e
  WHERE e.appointment_id = _appointment_id
  ORDER BY e.created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_encounter.id IS NULL THEN
    INSERT INTO public.encounters (
      patient_id, appointment_id, practitioner_id, encounter_type,
      symptoms, clerking_notes, status, facility_id
    ) VALUES (
      v_appt.patient_id, _appointment_id, v_user, 'consultation',
      NULLIF(pg_catalog.btrim(_symptoms), ''),
      NULLIF(pg_catalog.btrim(_clerking_notes), ''),
      'in_progress', v_facility
    )
    RETURNING * INTO v_encounter;
  ELSE
    IF v_encounter.facility_id IS NULL THEN
      UPDATE public.encounters
      SET facility_id = v_facility, updated_at = pg_catalog.now()
      WHERE id = v_encounter.id
      RETURNING * INTO v_encounter;
    END IF;
    IF v_encounter.facility_id IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Encounter belongs to a different facility context';
    END IF;
    UPDATE public.encounters
    SET practitioner_id = COALESCE(practitioner_id, v_user),
        symptoms = COALESCE(NULLIF(pg_catalog.btrim(_symptoms), ''), symptoms),
        clerking_notes = COALESCE(NULLIF(pg_catalog.btrim(_clerking_notes), ''), clerking_notes),
        status = CASE WHEN status = 'draft' THEN 'in_progress' ELSE status END,
        updated_at = pg_catalog.now()
    WHERE id = v_encounter.id
    RETURNING * INTO v_encounter;
  END IF;

  RETURN v_encounter.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.acknowledge_nursing_handover(_handover_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  h public.nursing_shift_handovers%ROWTYPE;
BEGIN
  IF uid IS NULL OR NOT(
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Nursing role required';
  END IF;

  SELECT * INTO h
  FROM public.nursing_shift_handovers
  WHERE id=_handover_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Handover not found'; END IF;
  IF h.facility_id IS NULL THEN RAISE EXCEPTION 'Handover facility attribution is unresolved'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF v_facility IS NULL OR h.facility_id IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Handover belongs to a different facility context';
    END IF;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=h.patient_id) THEN
    RAISE EXCEPTION 'Handover patient not found';
  END IF;
  IF h.acknowledged_at IS NOT NULL THEN
    RETURN jsonb_build_object('handover_id',h.id,'acknowledged_at',h.acknowledged_at,'acknowledged_by',h.incoming_officer);
  END IF;
  IF h.outgoing_officer=uid THEN RAISE EXCEPTION 'Outgoing officer cannot acknowledge their own handover'; END IF;

  UPDATE public.nursing_shift_handovers
  SET incoming_officer=uid,acknowledged_at=pg_catalog.now()
  WHERE id=h.id;

  PERFORM public.record_system_audit(
    'nursing_handover_acknowledged','clinical','nursing_shift_handovers',h.id,'info',
    jsonb_build_object('patient_id',h.patient_id,'incoming_officer',uid)
  );

  RETURN jsonb_build_object('handover_id',h.id,'acknowledged_at',pg_catalog.now(),'acknowledged_by',uid);
END;
$function$;

CREATE OR REPLACE FUNCTION public.acknowledge_vital_alert(_alert_id uuid)
RETURNS public.vital_alerts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  result public.vital_alerts;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Not authorized to acknowledge vital alerts';
  END IF;

  SELECT * INTO result
  FROM public.vital_alerts
  WHERE id=_alert_id
  FOR UPDATE;

  IF result.id IS NULL THEN RAISE EXCEPTION 'Vital alert not found'; END IF;
  IF result.facility_id IS NULL THEN RAISE EXCEPTION 'Vital alert facility attribution is unresolved'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF v_facility IS NULL OR result.facility_id IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Vital alert belongs to a different facility context';
    END IF;
  END IF;

  IF result.acknowledged_at IS NULL THEN
    UPDATE public.vital_alerts
    SET acknowledged_by=uid, acknowledged_at=pg_catalog.now()
    WHERE id=_alert_id
    RETURNING * INTO result;
  END IF;

  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.activate_patient_visit_coverage(
  _patient_id uuid,
  _source text,
  _appointment_id uuid DEFAULT NULL::uuid,
  _authorization_date date DEFAULT CURRENT_DATE
)
RETURNS public.patient_visit_authorizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public'
AS $function$
DECLARE
  coverage RECORD;
  result public.patient_visit_authorizations;
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_patient_facility uuid;
  v_appointment_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _source NOT IN ('appointment','accounts') THEN RAISE EXCEPTION 'Invalid activation source'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'accountant') OR public.has_role(uid,'front_desk')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
    OR public.has_role(uid,'lab_technician') OR public.has_role(uid,'radiologist')
    OR public.has_role(uid,'radiology_technician') OR public.has_role(uid,'pharmacist')
  ) THEN
    RAISE EXCEPTION 'Only authorised staff can activate visit coverage';
  END IF;

  SELECT facility_id INTO v_patient_facility
  FROM public.patients
  WHERE id=_patient_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient does not exist'; END IF;
  IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;

  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF v_facility IS NULL OR v_patient_facility IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Patient belongs to a different facility context';
    END IF;
  END IF;

  IF _appointment_id IS NOT NULL THEN
    SELECT facility_id INTO v_appointment_facility
    FROM public.appointments
    WHERE id=_appointment_id AND patient_id=_patient_id
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Appointment does not belong to this patient'; END IF;
    IF v_appointment_facility IS NULL THEN RAISE EXCEPTION 'Appointment facility attribution is unresolved'; END IF;
    IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin'))
       AND v_appointment_facility IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Appointment belongs to a different facility context';
    END IF;
  END IF;

  SELECT * INTO coverage FROM public.patient_coverage_details(_patient_id);
  IF coverage.coverage_type IS NULL THEN
    RAISE EXCEPTION 'Patient has no active insurance or partnered-company coverage';
  END IF;

  INSERT INTO public.patient_visit_authorizations(
    patient_id,authorization_date,coverage_type,payer_name,activated_by,
    activation_source,appointment_id,active
  )
  VALUES(
    _patient_id,_authorization_date,coverage.coverage_type,coverage.payer_name,uid,
    _source,_appointment_id,true
  )
  ON CONFLICT(patient_id,authorization_date) DO UPDATE SET
    coverage_type=EXCLUDED.coverage_type,
    payer_name=EXCLUDED.payer_name,
    activated_by=EXCLUDED.activated_by,
    activation_source=EXCLUDED.activation_source,
    appointment_id=COALESCE(EXCLUDED.appointment_id,patient_visit_authorizations.appointment_id),
    active=true
  RETURNING * INTO result;

  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admit_encounter_workflow(
  _encounter_id uuid,
  _reason text DEFAULT NULL::text,
  _ward text DEFAULT NULL::text,
  _emergency_override boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public'
AS $function$
DECLARE
  v_enc public.encounters%rowtype;
  v_admission uuid;
  v_override boolean := false;
  v_order record;
  v_ward_name text;
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_patient_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Admission is not permitted for this role';
  END IF;

  SELECT * INTO v_enc
  FROM public.encounters
  WHERE id = _encounter_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Encounter not found'; END IF;

  SELECT facility_id INTO v_patient_facility
  FROM public.patients
  WHERE id=v_enc.patient_id
  FOR UPDATE;
  IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;
  IF v_enc.facility_id IS NULL THEN RAISE EXCEPTION 'Encounter facility attribution is unresolved'; END IF;

  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF v_facility IS NULL OR v_enc.facility_id IS DISTINCT FROM v_facility OR v_patient_facility IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Encounter or patient belongs to a different facility context';
    END IF;
  END IF;

  IF v_enc.status = 'cancelled' THEN RAISE EXCEPTION 'Cancelled encounters cannot be admitted'; END IF;
  IF v_enc.admission_id IS NOT NULL THEN
    RETURN jsonb_build_object('admission_id',v_enc.admission_id,'override',false,'existing',true);
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_enc.patient_id::text, 0));

  IF EXISTS (
    SELECT 1 FROM public.admissions
    WHERE patient_id = v_enc.patient_id AND status = 'admitted'
  ) THEN
    RAISE EXCEPTION 'Patient already has an active admission';
  END IF;

  IF nullif(pg_catalog.btrim(_ward), '') IS NOT NULL THEN
    SELECT wu.name INTO v_ward_name
    FROM public.ward_units wu
    WHERE wu.active = true
      AND (
        lower(pg_catalog.btrim(wu.name)) = lower(pg_catalog.btrim(_ward))
        OR lower(pg_catalog.btrim(wu.code)) = lower(pg_catalog.btrim(_ward))
      )
    ORDER BY wu.name
    LIMIT 1;
    IF v_ward_name IS NULL THEN RAISE EXCEPTION 'Active ward not found'; END IF;
  END IF;

  SELECT coalesce(allow_treatment_before_deposit,false)
    and coalesce(admission_financial_override_enabled,false)
    and coalesce(allow_clinical_emergency_override,false)
    INTO v_override
  FROM public.facility_configuration
  WHERE id = 'default'
  LIMIT 1;

  v_override := coalesce(v_override,false) and coalesce(_emergency_override,true);

  INSERT INTO public.admissions(patient_id, encounter_id, ward, reason, admitted_by, status)
  VALUES(
    v_enc.patient_id,v_enc.id,v_ward_name,
    coalesce(nullif(pg_catalog.btrim(_reason),''),'Clinical admission'),
    uid,'admitted'
  )
  RETURNING id INTO v_admission;

  UPDATE public.encounters
  SET admission_id=v_admission,updated_at=pg_catalog.now()
  WHERE id=v_enc.id;

  IF v_override THEN
    FOR v_order IN
      SELECT * FROM public.service_orders
      WHERE encounter_id=v_enc.id AND status='pending_payment_approval'
      FOR UPDATE
    LOOP
      INSERT INTO public.billing_overrides(
        service_order_id,patient_id,department,related_entity_id,
        reason,overridden_by,approved_by,approved_at
      )
      VALUES(
        v_order.id,v_order.patient_id,v_order.department,v_order.related_entity_id,
        coalesce(nullif(pg_catalog.btrim(_reason),''),
                 'Emergency treatment before deposit'),
        uid,uid,pg_catalog.now()
      )
      ON CONFLICT(service_order_id) DO UPDATE SET
        reason=EXCLUDED.reason,
        overridden_by=EXCLUDED.overridden_by,
        approved_by=EXCLUDED.approved_by,
        approved_at=EXCLUDED.approved_at;

      UPDATE public.service_orders
      SET status='released',
          approved_at=pg_catalog.now(),
          approved_by=uid,
          released_at=pg_catalog.now(),
          released_by=uid,
          release_reason='Emergency admission financial override',
          notes=concat_ws(E'\\n',notes,'Emergency admission financial override: treatment released before deposit.'),
          updated_at=pg_catalog.now()
      WHERE id=v_order.id;

      INSERT INTO public.department_queues(
        service_order_id,patient_id,department,related_encounter_id,
        related_invoice_id,payment_required,payment_satisfied,priority,
        reason,created_by,queued_at,status
      )
      VALUES(
        v_order.id,v_order.patient_id,v_order.department,v_order.encounter_id,
        v_order.invoice_id,v_order.payment_required,TRUE,'normal',
        v_order.service_name,uid,pg_catalog.now(),'queued'
      )
      ON CONFLICT(service_order_id) DO UPDATE SET
        payment_satisfied=TRUE,
        status=CASE
          WHEN public.department_queues.status='cancelled' THEN 'queued'
          ELSE public.department_queues.status
        END,
        updated_at=pg_catalog.now();
    END LOOP;

    PERFORM public.record_system_audit(
      'admission_financial_override','admissions','admission',v_admission,'critical',
      jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'override',true)
    );
  END IF;

  PERFORM public.record_system_audit(
    'patient_admitted','admissions','admission',v_admission,'info',
    jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'financial_override',v_override)
  );

  INSERT INTO public.notifications(
    recipient_role,title,message,severity,category,link,related_patient_id,related_entity_id,metadata
  )
  VALUES
    ('nurse'::public.app_role,'New inpatient admission',
      'A patient has been admitted from a clinical encounter and requires inpatient handover.',
      CASE WHEN v_override THEN 'critical' ELSE 'high' END,
      'admission','/inpatient',v_enc.patient_id,v_admission,
      jsonb_build_object('encounter_id',v_enc.id,'admission_id',v_admission,'requires_acknowledgement',true)),
    ('specialist_nurse'::public.app_role,'New inpatient admission',
      'A patient has been admitted from a clinical encounter and requires inpatient handover.',
      CASE WHEN v_override THEN 'critical' ELSE 'high' END,
      'admission','/inpatient',v_enc.patient_id,v_admission,
      jsonb_build_object('encounter_id',v_enc.id,'admission_id',v_admission,'requires_acknowledgement',true)),
    ('midwife'::public.app_role,'New inpatient admission',
      'A patient has been admitted from a clinical encounter and requires inpatient handover.',
      CASE WHEN v_override THEN 'critical' ELSE 'high' END,
      'admission','/inpatient',v_enc.patient_id,v_admission,
      jsonb_build_object('encounter_id',v_enc.id,'admission_id',v_admission,'requires_acknowledgement',true));

  RETURN jsonb_build_object('admission_id',v_admission,'override',v_override,'status','admitted');
END;
$function$;

CREATE OR REPLACE FUNCTION public.amend_encounter_workflow(
  _encounter_id uuid,
  _symptoms text DEFAULT NULL::text,
  _clerking_notes text DEFAULT NULL::text,
  _principal_diagnosis text DEFAULT NULL::text,
  _treatment_plan text DEFAULT NULL::text,
  _reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_enc public.encounters%rowtype;
  v_patient_facility uuid;
  v_snapshot jsonb;
  v_next_version integer;
  v_has_permission boolean := false;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  SELECT * INTO v_enc
  FROM public.encounters
  WHERE id = _encounter_id
  FOR UPDATE;
  IF v_enc.id IS NULL THEN RAISE EXCEPTION 'Encounter not found'; END IF;

  SELECT facility_id INTO v_patient_facility
  FROM public.patients
  WHERE id=v_enc.patient_id
  FOR UPDATE;

  IF v_patient_facility IS NULL OR v_enc.facility_id IS NULL THEN
    RAISE EXCEPTION 'Encounter or patient facility attribution is unresolved';
  END IF;

  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF v_facility IS NULL OR v_enc.facility_id IS DISTINCT FROM v_facility OR v_patient_facility IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Encounter belongs to a different facility context';
    END IF;
  END IF;

  SELECT exists (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.role_permissions rp ON rp.role = ur.role
    JOIN public.permissions p ON p.permission_key = rp.permission_key
    WHERE ur.user_id = uid
      AND p.permission_key = 'encounters_amend'
      AND p.is_active = true
  ) INTO v_has_permission;

  IF v_enc.practitioner_id <> uid
     AND NOT public.has_role(uid,'admin')
     AND NOT public.has_role(uid,'it_admin')
     AND NOT v_has_permission THEN
    RAISE EXCEPTION 'You are not authorized to amend this encounter';
  END IF;

  IF v_enc.status <> 'completed' THEN RAISE EXCEPTION 'Only finalized encounters can be amended'; END IF;
  IF nullif(pg_catalog.btrim(_reason),'') IS NULL THEN RAISE EXCEPTION 'Amendment reason is required'; END IF;

  v_next_version := greatest(coalesce(v_enc.version_no,1),1) + 1;

  v_snapshot := jsonb_build_object(
    'encounter',to_jsonb(v_enc),
    'diagnoses',coalesce((
      SELECT jsonb_agg(to_jsonb(d) ORDER BY d.created_at,d.id)
      FROM public.diagnoses d WHERE d.encounter_id=v_enc.id
    ),'[]'::jsonb),
    'prescriptions',coalesce((
      SELECT jsonb_agg(to_jsonb(p) ORDER BY p.created_at,p.id)
      FROM public.prescriptions p WHERE p.encounter_id=v_enc.id
    ),'[]'::jsonb),
    'amendment_reason',pg_catalog.btrim(_reason)
  );

  INSERT INTO public.document_versions(entity_type,entity_id,version_no,action,snapshot,changed_by)
  VALUES('encounter',v_enc.id,v_next_version,'amendment',v_snapshot,uid);

  UPDATE public.encounters
  SET symptoms=nullif(pg_catalog.btrim(_symptoms),''),
      clerking_notes=nullif(pg_catalog.btrim(_clerking_notes),''),
      principal_diagnosis=nullif(pg_catalog.btrim(_principal_diagnosis),''),
      treatment_plan=nullif(pg_catalog.btrim(_treatment_plan),''),
      version_no=v_next_version,
      updated_at=pg_catalog.now()
  WHERE id=v_enc.id;

  PERFORM public.record_system_audit(
    'encounter_amended','clinical','encounter',v_enc.id,'warning',
    jsonb_build_object(
      'patient_id',v_enc.patient_id,
      'previous_version',greatest(coalesce(v_enc.version_no,1),1),
      'new_version',v_next_version,
      'reason',pg_catalog.btrim(_reason),
      'amended_by',uid
    )
  );

  RETURN jsonb_build_object(
    'encounter_id',v_enc.id,'status','completed','version_no',v_next_version,'amended_by',uid
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_child_facility_from_parent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_facility uuid;
  v_reconciliation boolean := coalesce(pg_catalog.current_setting('hms.facility_reconciliation', true), 'off') = 'on';
BEGIN
  IF tg_table_name='department_queues' THEN
    SELECT so.facility_id INTO v_facility
    FROM public.service_orders so WHERE so.id=new.service_order_id;
  ELSIF tg_table_name='lab_orders' THEN
    SELECT e.facility_id INTO v_facility
    FROM public.encounters e WHERE e.id=new.encounter_id;
    IF v_facility IS NULL THEN
      SELECT p.facility_id INTO v_facility FROM public.patients p WHERE p.id=new.patient_id;
    END IF;
  ELSIF tg_table_name='lab_results' THEN
    SELECT lo.facility_id INTO v_facility
    FROM public.lab_orders lo WHERE lo.id=new.lab_order_id;
  ELSIF tg_table_name='imaging_orders' THEN
    SELECT e.facility_id INTO v_facility
    FROM public.encounters e WHERE e.id=new.encounter_id;
    IF v_facility IS NULL THEN
      SELECT p.facility_id INTO v_facility FROM public.patients p WHERE p.id=new.patient_id;
    END IF;
  ELSIF tg_table_name='prescriptions' THEN
    SELECT e.facility_id INTO v_facility
    FROM public.encounters e WHERE e.id=new.encounter_id;
    IF v_facility IS NULL THEN
      SELECT p.facility_id INTO v_facility FROM public.patients p WHERE p.id=new.patient_id;
    END IF;
  ELSIF tg_table_name='diagnoses' THEN
    SELECT e.facility_id INTO v_facility
    FROM public.encounters e WHERE e.id=new.encounter_id;
    IF v_facility IS NULL THEN
      SELECT p.facility_id INTO v_facility FROM public.patients p WHERE p.id=new.patient_id;
    END IF;
  END IF;

  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'Parent clinical record has no facility attribution; reconcile the parent record first';
  END IF;

  IF new.facility_id IS NULL THEN
    IF tg_op='UPDATE' THEN
      RAISE EXCEPTION 'Facility attribution cannot be cleared';
    END IF;
    new.facility_id := v_facility;
  ELSIF new.facility_id<>v_facility
    AND NOT (
      v_reconciliation
      AND (public.current_user_has_role('admin') OR public.current_user_has_role('it_admin'))
    ) THEN
    RAISE EXCEPTION 'Facility lineage mismatch';
  END IF;

  RETURN new;
END;
$function$;

REVOKE ALL ON FUNCTION public.ensure_encounter_facility_attribution(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ensure_encounter_facility_attribution(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_encounter_workflow(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_encounter_workflow(uuid,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.start_appointment_encounter(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.start_appointment_encounter(uuid,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.acknowledge_nursing_handover(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_nursing_handover(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.acknowledge_vital_alert(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_vital_alert(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.activate_patient_visit_coverage(uuid,text,uuid,date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.activate_patient_visit_coverage(uuid,text,uuid,date) TO authenticated;
REVOKE ALL ON FUNCTION public.admit_encounter_workflow(uuid,text,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_encounter_workflow(uuid,text,text,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.amend_encounter_workflow(uuid,text,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.amend_encounter_workflow(uuid,text,text,text,text,text) TO authenticated;

-- Keep the intentional authenticated SECURITY DEFINER API surface explicit:
-- these functions remain authenticated-only and server-authorized; they are not
-- anonymous endpoints and do not grant cross-facility access to clinical roles.
