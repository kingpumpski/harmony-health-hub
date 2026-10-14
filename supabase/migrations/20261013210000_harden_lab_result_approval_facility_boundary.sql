BEGIN;

CREATE OR REPLACE FUNCTION public.approve_lab_result(_lab_result_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_global_admin boolean := public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'it_admin');
  v_patient_facility uuid;
  encounter_patient_id uuid;
  encounter_facility_id uuid;
  r public.lab_results%ROWTYPE;
  o public.lab_orders%ROWTYPE;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'it_admin')
    OR public.has_role(uid, 'lab_technician')
    OR public.has_role(uid, 'practitioner')
  ) THEN
    RAISE EXCEPTION 'Laboratory approval role required';
  END IF;

  IF v_facility IS NULL AND NOT v_global_admin THEN
    RAISE EXCEPTION 'Active facility context is required for laboratory result approval';
  END IF;

  SELECT * INTO r
  FROM public.lab_results
  WHERE id = _lab_result_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Laboratory result not found';
  END IF;

  IF r.status <> 'completed' THEN
    RAISE EXCEPTION 'Only completed results can be approved';
  END IF;

  SELECT * INTO o
  FROM public.lab_orders
  WHERE id = r.lab_order_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Laboratory order not found';
  END IF;

  IF r.facility_id IS NULL OR o.facility_id IS NULL
     OR r.facility_id IS DISTINCT FROM o.facility_id THEN
    RAISE EXCEPTION 'Laboratory result/order facility mismatch';
  END IF;
  IF NOT v_global_admin AND r.facility_id IS DISTINCT FROM v_facility THEN
    RAISE EXCEPTION 'Laboratory result belongs to a different facility context';
  END IF;

  IF r.patient_id IS NULL OR o.patient_id IS NULL
     OR r.patient_id IS DISTINCT FROM o.patient_id THEN
    RAISE EXCEPTION 'Laboratory result and order patient context do not match';
  END IF;

  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p
  WHERE p.id = o.patient_id
  FOR SHARE;
  IF NOT FOUND OR v_patient_facility IS NULL
     OR v_patient_facility IS DISTINCT FROM r.facility_id THEN
    RAISE EXCEPTION 'Laboratory patient facility mismatch';
  END IF;

  IF o.encounter_id IS NOT NULL THEN
    SELECT e.patient_id, e.facility_id
      INTO encounter_patient_id, encounter_facility_id
    FROM public.encounters e
    WHERE e.id = o.encounter_id
    FOR SHARE;

    IF encounter_patient_id IS NULL
       OR encounter_patient_id IS DISTINCT FROM o.patient_id THEN
      RAISE EXCEPTION 'Laboratory order encounter does not belong to patient';
    END IF;
    IF encounter_facility_id IS NULL
       OR encounter_facility_id IS DISTINCT FROM r.facility_id THEN
      RAISE EXCEPTION 'Laboratory encounter facility mismatch';
    END IF;
  END IF;

  IF o.status <> 'completed' THEN
    RAISE EXCEPTION 'Laboratory order must be completed before result approval';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.service_orders so
    WHERE so.related_entity_id = coalesce(o.parent_order_id, o.id)
      AND so.department = 'laboratory'
      AND so.patient_id = o.patient_id
      AND so.facility_id = r.facility_id
      AND so.status IN ('released', 'in_progress', 'completed')
  ) THEN
    RAISE EXCEPTION 'Laboratory billing release is required before result approval';
  END IF;

  UPDATE public.lab_results
  SET status = 'approved',
      approved_by = uid,
      approved_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  WHERE id = r.id AND status = 'completed';

  UPDATE public.lab_orders
  SET status = 'approved', updated_at = pg_catalog.now()
  WHERE id = o.id AND status = 'completed';

  PERFORM public.record_system_audit(
    CASE WHEN o.parent_order_id IS NULL THEN 'lab_result_approved' ELSE 'lab_panel_test_approved' END,
    'laboratory',
    CASE WHEN o.parent_order_id IS NULL THEN 'lab_orders' ELSE 'lab_test_groups' END,
    coalesce(o.parent_order_id, o.id),
    'info',
    pg_catalog.jsonb_build_object(
      'lab_order_id', o.id,
      'lab_result_id', r.id,
      'group_id', o.group_id,
      'test_id', o.lab_test_catalogue_id,
      'actor_id', uid
    )
  );

  IF o.ordered_by IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.recipient_user_id = o.ordered_by
      AND n.related_entity_id = o.id
      AND n.category = 'diagnostic_result'
      AND n.title = 'Laboratory result ready'
      AND n.is_read = false
  ) THEN
    INSERT INTO public.notifications(
      recipient_user_id, title, message, severity, category, link,
      related_patient_id, related_entity_id, metadata
    )
    VALUES (
      o.ordered_by,
      'Laboratory result ready',
      pg_catalog.format('The %s laboratory result is approved and ready for clinical review.', o.test_name),
      CASE WHEN coalesce(r.is_abnormal, false) THEN 'critical' ELSE 'info' END,
      'diagnostic_result',
      pg_catalog.format('/laboratory?patient=%s&order=%s&result=%s%s',
        o.patient_id, o.id, r.id,
        CASE WHEN o.encounter_id IS NOT NULL
          THEN pg_catalog.format('&encounter=%s', o.encounter_id)
          ELSE '' END),
      o.patient_id, o.id,
      pg_catalog.jsonb_build_object(
        'workflow', 'lab_result_review',
        'lab_result_id', r.id,
        'lab_order_id', o.id,
        'encounter_id', o.encounter_id,
        'is_abnormal', coalesce(r.is_abnormal, false),
        'requires_acknowledgement', true
      )
    );
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'lab_result_id', r.id,
    'lab_order_id', o.id,
    'patient_id', r.patient_id,
    'encounter_id', o.encounter_id,
    'status', 'approved'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.approve_lab_result(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_lab_result(uuid) TO authenticated;

COMMIT;
