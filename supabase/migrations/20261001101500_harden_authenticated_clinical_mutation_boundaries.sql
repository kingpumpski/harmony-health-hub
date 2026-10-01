-- Second tranche: close authenticated SECURITY DEFINER clinical mutation
-- boundaries identified by the production audit. These functions must never
-- locate a record globally and mutate it without proving facility lineage.

CREATE OR REPLACE FUNCTION public.claim_appointment(_appointment_id uuid)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog, public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  result public.appointments;
  v_patient_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin'::public.app_role)
    OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role)
    OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
  ) THEN RAISE EXCEPTION 'Only attending clinical officers may claim appointments'; END IF;
  IF v_facility IS NULL AND NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    RAISE EXCEPTION 'An active facility is required';
  END IF;

  SELECT * INTO result FROM public.appointments WHERE id=_appointment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found'; END IF;
  SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=result.patient_id FOR SHARE;
  IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;

  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF result.facility_id IS NULL OR result.facility_id IS DISTINCT FROM v_facility
       OR v_patient_facility IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Appointment or patient belongs to a different facility context';
    END IF;
  END IF;

  IF result.attending_officer_id IS NOT NULL AND result.attending_officer_id<>uid
     AND NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    RAISE EXCEPTION 'Appointment is already assigned to another officer';
  END IF;

  UPDATE public.appointments
  SET attending_officer_id=uid,
      claimed_at=coalesce(claimed_at,pg_catalog.now()),
      treatment_status=CASE WHEN treatment_status='scheduled' THEN 'claimed' ELSE treatment_status END,
      updated_at=pg_catalog.now()
  WHERE id=result.id
  RETURNING * INTO result;
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_appointment_workflow(
  _appointment_id uuid,
  _scheduled_at timestamp with time zone,
  _department text,
  _reason text,
  _treatment_status text,
  _treatment_notes text DEFAULT NULL::text
)
RETURNS public.appointments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog, public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  result public.appointments;
  v_patient_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _treatment_status NOT IN ('scheduled','claimed','in_progress','completed','cancelled','no_show') THEN
    RAISE EXCEPTION 'Invalid treatment status';
  END IF;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
    OR public.has_role(uid,'front_desk')
  ) THEN RAISE EXCEPTION 'You are not authorized to edit appointments'; END IF;

  SELECT * INTO result FROM public.appointments WHERE id=_appointment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Appointment not found'; END IF;
  SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=result.patient_id FOR SHARE;
  IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;

  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF v_facility IS NULL OR result.facility_id IS NULL
       OR result.facility_id IS DISTINCT FROM v_facility
       OR v_patient_facility IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Appointment or patient belongs to a different facility context';
    END IF;
  END IF;

  IF result.attending_officer_id IS DISTINCT FROM uid
     AND NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'front_desk')) THEN
    RAISE EXCEPTION 'Appointment is not assigned to this officer';
  END IF;

  UPDATE public.appointments
  SET scheduled_at=_scheduled_at,
      department=NULLIF(pg_catalog.btrim(_department),''),
      reason=NULLIF(pg_catalog.btrim(_reason),''),
      treatment_status=_treatment_status,
      treatment_notes=NULLIF(pg_catalog.btrim(_treatment_notes),''),
      started_at=CASE WHEN _treatment_status='in_progress' THEN coalesce(started_at,pg_catalog.now()) ELSE started_at END,
      completed_at=CASE WHEN _treatment_status='completed' THEN coalesce(completed_at,pg_catalog.now()) ELSE completed_at END,
      status=CASE WHEN _treatment_status='cancelled' THEN 'cancelled' WHEN _treatment_status='completed' THEN 'completed' ELSE status END,
      updated_at=pg_catalog.now()
  WHERE id=result.id
  RETURNING * INTO result;
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.assign_ward_bed(_bed_id uuid,_patient_id uuid,_admission_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog, public'
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_facility uuid:=public.current_user_facility_id();
  v_admission_id uuid:=_admission_id;
  v_bed_facility uuid;
  v_patient_facility uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
          OR public.has_role(uid,'nurse') OR public.has_role(uid,'specialist_nurse')) THEN
    RAISE EXCEPTION 'Nursing role required';
  END IF;
  IF _bed_id IS NULL OR _patient_id IS NULL THEN RAISE EXCEPTION 'Bed and patient are required'; END IF;

  SELECT facility_id INTO v_bed_facility FROM public.ward_beds WHERE id=_bed_id FOR SHARE;
  IF v_bed_facility IS NULL THEN RAISE EXCEPTION 'Bed not found or facility attribution is unresolved'; END IF;
  SELECT facility_id INTO v_patient_facility FROM public.patients WHERE id=_patient_id FOR SHARE;
  IF v_patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;

  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF v_facility IS NULL OR v_bed_facility IS DISTINCT FROM v_facility
       OR v_patient_facility IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Bed or patient belongs to a different facility context';
    END IF;
  END IF;

  IF v_admission_id IS NULL THEN
    SELECT a.id INTO v_admission_id
    FROM public.admissions a
    WHERE a.patient_id=_patient_id AND a.status='admitted'
      AND (a.facility_id=v_facility OR public.has_role(uid,'admin') OR public.has_role(uid,'it_admin'))
    ORDER BY a.admitted_at DESC NULLS LAST
    LIMIT 1;
  END IF;
  IF v_admission_id IS NULL THEN RAISE EXCEPTION 'Active admission not found for patient'; END IF;

  RETURN public.transfer_patient_ward_bed_workflow(_patient_id,v_admission_id,_bed_id,NULL,NULL,NULL);
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_lab_result(_lab_result_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog, public'
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_facility uuid:=public.current_user_facility_id();
  r public.lab_results%ROWTYPE;
  o public.lab_orders%ROWTYPE;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'lab_technician') OR public.has_role(uid,'practitioner')
  ) THEN RAISE EXCEPTION 'Laboratory approval role required'; END IF;

  SELECT * INTO r FROM public.lab_results WHERE id=_lab_result_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory result not found'; END IF;
  SELECT * INTO o FROM public.lab_orders WHERE id=r.lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF r.facility_id IS NULL OR o.facility_id IS NULL THEN RAISE EXCEPTION 'Laboratory facility attribution is unresolved'; END IF;
  IF r.facility_id IS DISTINCT FROM o.facility_id THEN RAISE EXCEPTION 'Laboratory result and order facility mismatch'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF v_facility IS NULL OR r.facility_id IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Laboratory result belongs to a different facility context';
    END IF;
  END IF;
  IF r.status<>'completed' THEN RAISE EXCEPTION 'Only completed results can be approved'; END IF;
  IF o.status<>'completed' THEN RAISE EXCEPTION 'Laboratory order must be completed before result approval'; END IF;

  UPDATE public.lab_results
  SET status='approved',approved_by=uid,approved_at=pg_catalog.now(),updated_at=pg_catalog.now()
  WHERE id=r.id AND status='completed';
  UPDATE public.lab_orders SET status='approved',updated_at=pg_catalog.now()
  WHERE id=o.id AND status='completed';

  IF o.ordered_by IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.notifications
    WHERE recipient_user_id=o.ordered_by AND related_entity_id=o.id
      AND category='diagnostic_result' AND title='Laboratory result ready' AND is_read=false
  ) THEN
    INSERT INTO public.notifications(
      recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata
    ) VALUES(
      o.ordered_by,'Laboratory result ready',
      format('The %s laboratory result is approved and ready for clinical review.',o.test_name),
      CASE WHEN coalesce(r.is_abnormal,false) THEN 'critical' ELSE 'info' END,
      'diagnostic_result',
      format('/laboratory?patient=%s&order=%s&result=%s%s',o.patient_id,o.id,r.id,
        CASE WHEN o.encounter_id IS NOT NULL THEN format('&encounter=%s',o.encounter_id) ELSE '' END),
      o.patient_id,o.id,
      jsonb_build_object('workflow','lab_result_review','lab_result_id',r.id,'lab_order_id',o.id,
        'encounter_id',o.encounter_id,'is_abnormal',coalesce(r.is_abnormal,false),'requires_acknowledgement',true)
    );
  END IF;
  RETURN jsonb_build_object('lab_result_id',r.id,'lab_order_id',o.id,'encounter_id',o.encounter_id,'status','approved');
END;
$function$;

CREATE OR REPLACE FUNCTION public.transition_medication_administration(
  _record_id uuid,_status text,_reason text DEFAULT NULL::text,_notes text DEFAULT NULL::text,_witnessed_by uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog, public'
AS $function$
DECLARE
  r public.medication_administrations%ROWTYPE;
  p public.prescriptions%ROWTYPE;
  uid uuid:=auth.uid();
  v_facility uuid:=public.current_user_facility_id();
  overdue boolean;
  v_interval interval;
  v_next timestamptz;
  v_end timestamptz;
BEGIN
  IF uid IS NULL OR NOT(
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife') OR public.has_role(uid,'specialist_nurse')
    OR public.has_role(uid,'pharmacist')
  ) THEN RAISE EXCEPTION 'Authorised clinical role required'; END IF;
  IF _status NOT IN ('administered','held','refused','omitted','not_given','cancelled') THEN
    RAISE EXCEPTION 'Unsupported medication administration status';
  END IF;

  SELECT * INTO r FROM public.medication_administrations WHERE id=_record_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Medication administration record not found'; END IF;
  IF r.facility_id IS NULL THEN RAISE EXCEPTION 'Medication administration facility attribution is unresolved'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF v_facility IS NULL OR r.facility_id IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Medication administration belongs to a different facility context';
    END IF;
  END IF;
  IF r.patient_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.patients WHERE id=r.patient_id AND coalesce(status,'active')<>'inactive'
  ) THEN RAISE EXCEPTION 'Medication patient not found or inactive'; END IF;

  IF r.prescription_id IS NOT NULL THEN
    SELECT * INTO p FROM public.prescriptions WHERE id=r.prescription_id FOR UPDATE;
    IF NOT FOUND OR p.patient_id<>r.patient_id THEN RAISE EXCEPTION 'Medication prescription does not match patient'; END IF;
    IF p.facility_id IS NULL OR p.facility_id IS DISTINCT FROM r.facility_id THEN
      RAISE EXCEPTION 'Medication prescription facility lineage is unresolved or mismatched';
    END IF;
    IF p.status IN ('cancelled','voided') THEN RAISE EXCEPTION 'Cannot administer a cancelled prescription'; END IF;
  END IF;

  overdue:=r.scheduled_at IS NOT NULL AND pg_catalog.now()>r.scheduled_at+make_interval(mins=>r.due_window_minutes);
  IF _status='administered' AND r.locked_at IS NOT NULL THEN
    RAISE EXCEPTION 'Medication slot is locked. An authorised reopening with explanation is required.';
  END IF;
  IF _status IN ('held','refused','omitted','not_given') AND r.locked_at IS NULL AND overdue THEN
    UPDATE public.medication_administrations SET locked_at=pg_catalog.now(),
      lock_reason=coalesce(_reason,'Late medication event requires explanation'),updated_at=pg_catalog.now()
    WHERE id=_record_id;
    RAISE EXCEPTION 'Medication slot has elapsed. Reopen it with an authorised explanation before documenting the event.';
  END IF;

  IF _status='administered' THEN
    UPDATE public.medication_administrations
    SET status='administered',administered_at=pg_catalog.now(),administered_by=uid,
      witnessed_by=coalesce(_witnessed_by,witnessed_by),
      reason=nullif(pg_catalog.btrim(coalesce(_reason,'')),''),
      notes=coalesce(_notes,notes),updated_at=pg_catalog.now()
    WHERE id=_record_id RETURNING * INTO r;

    IF r.prescription_id IS NOT NULL THEN
      v_interval:=public.medication_frequency_interval(p.frequency);
      v_end:=public.prescription_duration_end(p.created_at,p.duration);
      v_next:=pg_catalog.now()+v_interval;
      IF v_interval IS NOT NULL AND (v_end IS NULL OR v_next<v_end) AND NOT EXISTS(
        SELECT 1 FROM public.medication_administrations ma
        WHERE ma.prescription_id=r.prescription_id AND ma.scheduled_at=v_next
      ) THEN
        INSERT INTO public.medication_administrations(
          patient_id,prescription_id,medication_name,dose,route,scheduled_at,notes,due_window_minutes,facility_id
        ) VALUES(
          r.patient_id,r.prescription_id,coalesce(nullif(pg_catalog.btrim(p.medication_name),''),pg_catalog.btrim(p.medication)),
          p.dosage,p.route,v_next,'Automatically scheduled after documented administration',r.due_window_minutes,r.facility_id
        );
      END IF;
    END IF;
  ELSE
    UPDATE public.medication_administrations
    SET status=_status,reason=nullif(pg_catalog.btrim(coalesce(_reason,'')),''),
      notes=coalesce(_notes,notes),updated_at=pg_catalog.now()
    WHERE id=_record_id RETURNING * INTO r;
  END IF;

  PERFORM public.record_system_audit(
    'medication_administration_'||_status,'clinical','medication_administrations',_record_id,
    CASE WHEN _status='administered' THEN 'info' ELSE 'warning' END,
    jsonb_build_object('record_id',_record_id,'patient_id',r.patient_id,'prescription_id',r.prescription_id,
      'administered_by',uid,'timestamp',pg_catalog.now(),'reason',r.reason,'witnessed_by',r.witnessed_by,
      'next_scheduled_at',v_next)
  );
  RETURN jsonb_build_object('id',r.id,'status',r.status,'administered_by',r.administered_by,
    'administered_at',r.administered_at,'next_scheduled_at',v_next);
END;
$function$;

CREATE OR REPLACE FUNCTION public.reopen_medication_administration(_record_id uuid,_reason text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog, public'
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_facility uuid:=public.current_user_facility_id();
  v_record public.medication_administrations%ROWTYPE;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
          OR public.has_role(uid,'practitioner') OR public.has_role(uid,'nurse')
          OR public.has_role(uid,'midwife')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF length(pg_catalog.btrim(coalesce(_reason,'')))<3 THEN RAISE EXCEPTION 'Reopen reason is required'; END IF;
  SELECT * INTO v_record FROM public.medication_administrations WHERE id=_record_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Medication record not found'; END IF;
  IF v_record.facility_id IS NULL THEN RAISE EXCEPTION 'Medication administration facility attribution is unresolved'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF v_facility IS NULL OR v_record.facility_id IS DISTINCT FROM v_facility THEN
      RAISE EXCEPTION 'Medication administration belongs to a different facility context';
    END IF;
  END IF;
  UPDATE public.medication_administrations
  SET locked_at=NULL,lock_reason=NULL,reopened_at=pg_catalog.now(),reopen_reason=pg_catalog.btrim(_reason),updated_at=pg_catalog.now()
  WHERE id=_record_id;
  PERFORM public.record_system_audit(
    'medication_administration_reopened','clinical','medication_administrations',_record_id,'warning',
    jsonb_build_object('reason',pg_catalog.btrim(_reason),'reopened_by',uid)
  );
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_appointment(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.claim_appointment(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.update_appointment_workflow(uuid,timestamp with time zone,text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_appointment_workflow(uuid,timestamp with time zone,text,text,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.assign_ward_bed(uuid,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.assign_ward_bed(uuid,uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.approve_lab_result(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.approve_lab_result(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.transition_medication_administration(uuid,text,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.transition_medication_administration(uuid,text,text,text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.reopen_medication_administration(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reopen_medication_administration(uuid,text) TO authenticated;
