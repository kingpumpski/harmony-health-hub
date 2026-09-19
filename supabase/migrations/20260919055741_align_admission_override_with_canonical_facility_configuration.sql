-- Keep the admission/emergency override workflow bound to the canonical
-- administrator-controlled facility_configuration table used by the Settings UI.
CREATE OR REPLACE FUNCTION public.admit_encounter_workflow(
  _encounter_id UUID,
  _reason TEXT DEFAULT NULL,
  _ward TEXT DEFAULT NULL,
  _emergency_override BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_enc public.encounters%ROWTYPE;
  v_admission UUID;
  v_override BOOLEAN := FALSE;
  v_order RECORD;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner')
    OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')
    OR public.has_role(auth.uid(),'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Admission is not permitted for this role'; END IF;

  SELECT * INTO v_enc FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
  IF v_enc.id IS NULL THEN RAISE EXCEPTION 'Encounter not found'; END IF;
  IF v_enc.status = 'cancelled' THEN RAISE EXCEPTION 'Cancelled encounters cannot be admitted'; END IF;
  IF v_enc.admission_id IS NOT NULL THEN
    RETURN jsonb_build_object('admission_id',v_enc.admission_id,'override',FALSE,'existing',TRUE);
  END IF;

  SELECT COALESCE(allow_treatment_before_deposit,FALSE)
      AND COALESCE(admission_financial_override_enabled,FALSE)
      AND COALESCE(allow_clinical_emergency_override,FALSE)
    INTO v_override
  FROM public.facility_configuration
  LIMIT 1;
  v_override := COALESCE(v_override,FALSE) AND COALESCE(_emergency_override,TRUE);

  INSERT INTO public.admissions(patient_id,encounter_id,ward,reason,admitted_by,status)
  VALUES(v_enc.patient_id,v_enc.id,NULLIF(btrim(_ward),''),
         COALESCE(NULLIF(btrim(_reason),''),'Clinical admission'),auth.uid(),'admitted')
  RETURNING id INTO v_admission;

  UPDATE public.encounters SET admission_id=v_admission,updated_at=now() WHERE id=v_enc.id;

  IF v_override THEN
    FOR v_order IN
      SELECT * FROM public.service_orders
      WHERE encounter_id=v_enc.id AND status='pending_payment_approval'
      FOR UPDATE
    LOOP
      INSERT INTO public.billing_overrides(
        service_order_id,patient_id,department,related_entity_id,
        reason,overridden_by,approved_by,approved_at)
      VALUES(v_order.id,v_order.patient_id,v_order.department,v_order.related_entity_id,
             COALESCE(NULLIF(btrim(_reason),''),'Emergency treatment before deposit'),
             auth.uid(),auth.uid(),now())
      ON CONFLICT(service_order_id) DO UPDATE
      SET reason=EXCLUDED.reason,overridden_by=EXCLUDED.overridden_by,
          approved_by=EXCLUDED.approved_by,approved_at=EXCLUDED.approved_at;

      UPDATE public.service_orders
      SET status='released',approved_at=now(),approved_by=auth.uid(),
          released_at=now(),released_by=auth.uid(),
          release_reason='Emergency admission financial override',
          notes=concat_ws(E'\n',notes,'Emergency admission financial override: treatment released before deposit.'),
          updated_at=now()
      WHERE id=v_order.id;

      INSERT INTO public.department_queues(
        service_order_id,patient_id,department,related_encounter_id,
        related_invoice_id,payment_required,payment_satisfied,priority,
        reason,created_by,queued_at,status)
      VALUES(v_order.id,v_order.patient_id,v_order.department,v_order.encounter_id,
             v_order.invoice_id,v_order.payment_required,TRUE,'normal',
             v_order.service_name,auth.uid(),now(),'queued')
      ON CONFLICT(service_order_id) DO UPDATE
      SET payment_satisfied=TRUE,
          status=CASE WHEN public.department_queues.status='cancelled' THEN 'queued'
                      ELSE public.department_queues.status END,
          updated_at=now();
    END LOOP;

    PERFORM public.record_system_audit(
      'admission_financial_override','admissions','admission',v_admission,'critical',
      jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'override',TRUE));
  END IF;

  PERFORM public.record_system_audit(
    'patient_admitted','admissions','admission',v_admission,'info',
    jsonb_build_object('encounter_id',v_enc.id,'patient_id',v_enc.patient_id,'financial_override',v_override));

  RETURN jsonb_build_object('admission_id',v_admission,'override',v_override,'status','admitted');
END;
$$;

REVOKE ALL ON FUNCTION public.admit_encounter_workflow(UUID,TEXT,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admit_encounter_workflow(UUID,TEXT,TEXT,BOOLEAN) TO authenticated;