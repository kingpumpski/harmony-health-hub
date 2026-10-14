-- Reconcile the final laboratory approval implementation with patient/order/result facility lineage.
-- This migration preserves audit and notification behavior while failing closed on ambiguous facility attribution.
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
  r public.lab_results%ROWTYPE;
  o public.lab_orders%ROWTYPE;
  v_patient_facility uuid;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid, 'admin'::public.app_role)
    OR public.has_role(uid, 'it_admin'::public.app_role)
    OR public.has_role(uid, 'system_superuser'::public.app_role)
    OR public.has_role(uid, 'lab_technician'::public.app_role)
    OR public.has_role(uid, 'practitioner'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Laboratory approval role required';
  END IF;

  SELECT * INTO r
  FROM public.lab_results
  WHERE id = _lab_result_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Laboratory result not found';
  END IF;

  SELECT * INTO o
  FROM public.lab_orders
  WHERE id = r.lab_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Laboratory order not found';
  END IF;

  IF r.status <> 'completed' OR o.status <> 'completed' THEN
    RAISE EXCEPTION 'Only completed results and orders can be approved';
  END IF;

  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p
  WHERE p.id = o.patient_id
  FOR SHARE;

  IF NOT FOUND OR v_patient_facility IS NULL OR o.facility_id IS NULL OR r.facility_id IS NULL THEN
    RAISE EXCEPTION 'Laboratory patient, order, and result facility attribution is unresolved';
  END IF;

  IF v_patient_facility IS DISTINCT FROM o.facility_id
     OR r.facility_id IS DISTINCT FROM o.facility_id THEN
    RAISE EXCEPTION 'Laboratory result facility mismatch across patient, order, and result';
  END IF;

  IF NOT (
    public.has_role(uid, 'admin'::public.app_role)
    OR public.has_role(uid, 'it_admin'::public.app_role)
    OR public.has_role(uid, 'system_superuser'::public.app_role)
  ) AND (
    v_facility IS NULL OR o.facility_id IS DISTINCT FROM v_facility
  ) THEN
    RAISE EXCEPTION 'Laboratory result does not match the active facility context';
  END IF;

  UPDATE public.lab_results
  SET status = 'approved',
      approved_by = uid,
      approved_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  WHERE id = r.id AND status = 'completed';

  UPDATE public.lab_orders
  SET status = 'approved',
      updated_at = pg_catalog.now()
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
      'actor_id', uid,
      'facility_id', o.facility_id
    )
  );

  IF o.ordered_by IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.notifications
    WHERE recipient_user_id = o.ordered_by
      AND related_entity_id = o.id
      AND category = 'diagnostic_result'
      AND title = 'Laboratory result ready'
      AND is_read = false
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
      pg_catalog.format('/laboratory?patient=%s&order=%s&result=%s', o.patient_id, o.id, r.id),
      o.patient_id,
      o.id,
      pg_catalog.jsonb_build_object(
        'workflow', 'lab_result_review',
        'lab_result_id', r.id,
        'lab_order_id', o.id,
        'encounter_id', o.encounter_id,
        'panel_id', o.group_id,
        'parent_order_id', o.parent_order_id,
        'is_abnormal', coalesce(r.is_abnormal, false),
        'requires_acknowledgement', true
      )
    );
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'lab_result_id', r.id,
    'lab_order_id', o.id,
    'encounter_id', o.encounter_id,
    'status', 'approved'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.approve_lab_result(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_lab_result(uuid) TO authenticated;

COMMIT;