-- Harden encounter admission so canonical inpatient ward context is validated
-- and concurrent duplicate admissions are serialized without requiring a new
-- database constraint that could fail on legacy duplicate data.
CREATE OR REPLACE FUNCTION public.admit_encounter_workflow(
  _encounter_id uuid,
  _reason text DEFAULT NULL,
  _ward text DEFAULT NULL,
  _emergency_override boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_enc public.encounters%ROWTYPE;
  v_admission uuid;
  v_override boolean := false;
  v_order record;
  v_ward_id uuid;
  v_existing_admission uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'practitioner')
    OR public.has_role(auth.uid(),'nurse')
    OR public.has_role(auth.uid(),'midwife')
    OR public.has_role(auth.uid(),'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Admission is not permitted for this role';
  END IF;

  SELECT * INTO v_enc
  FROM public.encounters
  WHERE id=_encounter_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Encounter not found';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id=v_enc.patient_id
  ) THEN
    RAISE EXCEPTION 'Encounter patient not found';
  END IF;

  IF v_enc.status='cancelled' THEN
    RAISE EXCEPTION 'Cancelled encounters cannot be admitted';
  END IF;

  -- Idempotent replay: if this encounter is already linked, verify the
  -- admission still belongs to the same patient before returning it.
  IF v_enc.admission_id IS NOT NULL THEN
    SELECT id INTO v_admission
    FROM public.admissions
    WHERE id=v_enc.admission_id
      AND patient_id=v_enc.patient_id;

    IF v_admission IS NULL THEN
      RAISE EXCEPTION 'Encounter admission linkage is inconsistent';
    END IF;

    RETURN jsonb_build_object(
      'admission_id',v_admission,
      'override',FALSE,
      'existing',TRUE
    );
  END IF;

  -- Serialize admissions for the same patient so two concurrent encounters
  -- cannot both create a new active inpatient admission.
  PERFORM pg_advisory_xact_lock(
    hashtextextended(v_enc.patient_id::text, 0)
  );

  SELECT a.id INTO v_existing_admission
  FROM public.admissions a
  WHERE a.patient_id=v_enc.patient_id
    AND a.status='admitted'
  ORDER BY a.admitted_at DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_existing_admission IS NOT NULL THEN
    RAISE EXCEPTION 'Patient already has an active inpatient admission';
  END IF;

  -- Ward names/codes are legacy-compatible inputs, but the canonical ward
  -- source is ward_units. Do not reintroduce public.wards here.
  IF NULLIF(btrim(_ward),'') IS NOT NULL THEN
    SELECT id INTO v_ward_id
    FROM public.ward_units
    WHERE active=true
      AND (
        id::text = btrim(_ward)
        OR lower(btrim(name)) = lower(btrim(_ward))
        OR lower(btrim(code)) = lower(btrim(_ward))
      )
    ORDER BY CASE
      WHEN id::text = btrim(_ward) THEN 0
      WHEN lower(btrim(code)) = lower(btrim(_ward)) THEN 1
      ELSE 2
    END
    LIMIT 1;

    IF v_ward_id IS NULL THEN
      RAISE EXCEPTION 'Ward not found in canonical ward units';
    END IF;
  END IF;

  SELECT COALESCE(
    allow_treatment_before_deposit,FALSE
  )
  AND COALESCE(admission_financial_override_enabled,FALSE)
  AND COALESCE(allow_clinical_emergency_override,FALSE)
  INTO v_override
  FROM public.facility_configuration
  WHERE id='default'
  LIMIT 1;

  v_override:=COALESCE(v_override,FALSE)
    AND COALESCE(_emergency_override,TRUE);

  INSERT INTO public.admissions(
    patient_id,
    encounter_id,
    ward,
    reason,
    admitted_by,
    status
  )
  VALUES (
    v_enc.patient_id,
    v_enc.id,
    CASE WHEN v_ward_id IS NULL THEN NULL ELSE
      (SELECT w.name FROM public.ward_units w WHERE w.id=v_ward_id)
    END,
    COALESCE(NULLIF(btrim(_reason),''),'Clinical admission'),
    auth.uid(),
    'admitted'
  )
  RETURNING id INTO v_admission;

  UPDATE public.encounters
  SET admission_id=v_admission,updated_at=now()
  WHERE id=v_enc.id;

  IF v_override THEN
    FOR v_order IN
      SELECT *
      FROM public.service_orders
      WHERE encounter_id=v_enc.id
        AND status='pending_payment_approval'
      FOR UPDATE
    LOOP
      INSERT INTO public.billing_overrides(
        service_order_id,
        patient_id,
        department,
        related_entity_id,
        reason,
        overridden_by,
        approved_by,
        approved_at
      )
      VALUES(
        v_order.id,
        v_order.patient_id,
        v_order.department,
        v_order.related_entity_id,
        COALESCE(
          NULLIF(btrim(_reason),''),
          'Emergency treatment before deposit'
        ),
        auth.uid(),
        auth.uid(),
        now()
      )
      ON CONFLICT(service_order_id) DO UPDATE SET
        reason=EXCLUDED.reason,
        overridden_by=EXCLUDED.overridden_by,
        approved_by=EXCLUDED.approved_by,
        approved_at=EXCLUDED.approved_at;

      UPDATE public.service_orders
      SET status='released',
          approved_at=now(),
          approved_by=auth.uid(),
          released_at=now(),
          released_by=auth.uid(),
          release_reason='Emergency admission financial override',
          notes=concat_ws(
            E'\n',
            notes,
            'Emergency admission financial override: treatment released before deposit.'
          ),
          updated_at=now()
      WHERE id=v_order.id;

      INSERT INTO public.department_queues(
        service_order_id,
        patient_id,
        department,
        related_encounter_id,
        related_invoice_id,
        payment_required,
        payment_satisfied,
        priority,
        reason,
        created_by,
        queued_at,
        status
      )
      VALUES(
        v_order.id,
        v_order.patient_id,
        v_order.department,
        v_order.encounter_id,
        v_order.invoice_id,
        v_order.payment_required,
        TRUE,
        'normal',
        v_order.service_name,
        auth.uid(),
        now(),
        'queued'
      )
      ON CONFLICT(service_order_id) DO UPDATE SET
        payment_satisfied=TRUE,
        status=CASE
          WHEN public.department_queues.status='cancelled'
          THEN 'queued'
          ELSE public.department_queues.status
        END,
        updated_at=now();
    END LOOP;

    PERFORM public.record_system_audit(
      'admission_financial_override',
      'admissions',
      'admission',
      v_admission,
      'critical',
      jsonb_build_object(
        'encounter_id',v_enc.id,
        'patient_id',v_enc.patient_id,
        'override',TRUE
      )
    );
  END IF;

  PERFORM public.record_system_audit(
    'patient_admitted',
    'admissions',
    'admission',
    v_admission,
    'info',
    jsonb_build_object(
      'encounter_id',v_enc.id,
      'patient_id',v_enc.patient_id,
      'ward_id',v_ward_id,
      'financial_override',v_override
    )
  );

  RETURN jsonb_build_object(
    'admission_id',v_admission,
    'override',v_override,
    'status','admitted',
    'ward_id',v_ward_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.admit_encounter_workflow(uuid,text,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admit_encounter_workflow(uuid,text,text,boolean) TO authenticated;
