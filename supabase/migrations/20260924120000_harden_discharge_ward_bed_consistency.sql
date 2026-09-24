-- Keep the canonical ward-bed occupancy state consistent with admission discharge.
-- Branch-only migration; production is unchanged until explicitly deployed.

CREATE OR REPLACE FUNCTION public.discharge_admission_workflow(
  _admission_id uuid,
  _summary text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  a public.admissions%ROWTYPE;
  p public.patients%ROWTYPE;
  n uuid;
  v_bed_id uuid;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
  ) THEN
    RAISE EXCEPTION 'Admission discharge is not permitted';
  END IF;

  SELECT * INTO a
  FROM public.admissions
  WHERE id=_admission_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Admission not found';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.patients WHERE id=a.patient_id
  ) THEN
    RAISE EXCEPTION 'Admission patient not found';
  END IF;

  IF a.status='discharged' THEN
    SELECT wb.id INTO v_bed_id
    FROM public.ward_beds wb
    WHERE wb.admission_id=a.id
      AND wb.patient_id=a.patient_id
    ORDER BY wb.occupied_at DESC NULLS LAST
    LIMIT 1
    FOR UPDATE;

    IF v_bed_id IS NOT NULL THEN
      UPDATE public.ward_beds
      SET patient_id=NULL,
          admission_id=NULL,
          status='cleaning',
          released_at=COALESCE(released_at,now()),
          updated_at=now()
      WHERE id=v_bed_id
        AND admission_id=a.id
        AND patient_id=a.patient_id;
    END IF;

    SELECT id INTO n
    FROM public.notifications
    WHERE related_entity_id=a.id
      AND category='payment'
      AND recipient_role='accountant'
      AND metadata->>'workflow'='discharge_billing_handoff'
    ORDER BY created_at DESC
    LIMIT 1;

    RETURN jsonb_build_object(
      'admission_id',a.id,
      'patient_id',a.patient_id,
      'status','discharged',
      'billing_handoff','pending',
      'existing',TRUE,
      'notification_id',n,
      'bed_released',v_bed_id IS NOT NULL
    );
  END IF;

  IF a.status<>'admitted' THEN
    RAISE EXCEPTION 'Admission is not active';
  END IF;

  -- Lock the canonical bed through the admission linkage, not through
  -- the legacy free-text admissions.bed field.
  SELECT wb.id INTO v_bed_id
  FROM public.ward_beds wb
  WHERE wb.admission_id=a.id
    AND wb.patient_id=a.patient_id
  ORDER BY wb.occupied_at DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  UPDATE public.admissions
  SET status='discharged',
      discharged_at=now(),
      discharge_summary=COALESCE(
        NULLIF(btrim(_summary),''),
        'Discharged from inpatient admission.'
      ),
      updated_at=now()
  WHERE id=a.id;

  IF v_bed_id IS NOT NULL THEN
    UPDATE public.ward_beds
    SET patient_id=NULL,
        admission_id=NULL,
        status='cleaning',
        released_at=now(),
        updated_at=now()
    WHERE id=v_bed_id
      AND admission_id=a.id
      AND patient_id=a.patient_id;
  END IF;

  SELECT * INTO p FROM public.patients WHERE id=a.patient_id;

  SELECT id INTO n
  FROM public.notifications
  WHERE related_entity_id=a.id
    AND category='payment'
    AND recipient_role='accountant'
    AND metadata->>'workflow'='discharge_billing_handoff'
  ORDER BY created_at DESC
  LIMIT 1;

  IF n IS NULL THEN
    INSERT INTO public.notifications(
      recipient_role,title,message,severity,category,link,
      related_patient_id,related_entity_id,metadata
    )
    VALUES(
      'accountant',
      'Discharged patient ready for billing reconciliation',
      format(
        '%s (%s) has been discharged. Reconcile the complete patient bill, including inpatient services, before settlement.',
        COALESCE(p.first_name||' '||p.last_name,'Patient'),
        COALESCE(p.patient_code,'no patient code')
      ),
      'warning','payment','/billing',a.patient_id,a.id,
      jsonb_build_object(
        'workflow','discharge_billing_handoff',
        'admission_id',a.id,
        'discharged_at',now()
      )
    )
    RETURNING id INTO n;
  END IF;

  PERFORM public.record_system_audit(
    'patient_discharged',
    'admissions',
    'admission',
    a.id,
    'info',
    jsonb_build_object(
      'patient_id',a.patient_id,
      'billing_handoff_notification_id',n,
      'ward_bed_released',v_bed_id
    )
  );

  RETURN jsonb_build_object(
    'admission_id',a.id,
    'patient_id',a.patient_id,
    'status','discharged',
    'billing_handoff','pending',
    'notification_id',n,
    'bed_released',v_bed_id IS NOT NULL,
    'bed_id',v_bed_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.discharge_admission_workflow(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.discharge_admission_workflow(uuid,text) TO authenticated;
