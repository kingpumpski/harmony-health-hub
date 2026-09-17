-- Bridge completed imaging reports back to the clinician who requested the study.
-- Uses the existing notifications table; no new notification service or table is introduced.

CREATE OR REPLACE FUNCTION public.complete_imaging_order(
  _imaging_order_id uuid,
  _report text,
  _impression text
)
RETURNS public.imaging_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.imaging_orders;
  v_service public.service_orders;
  v_encounter_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_clinical_staff(auth.uid()) THEN
    RAISE EXCEPTION 'Clinical staff required';
  END IF;
  IF NULLIF(trim(COALESCE(_report,'')),'') IS NULL
     AND NULLIF(trim(COALESCE(_impression,'')),'') IS NULL THEN
    RAISE EXCEPTION 'A report or impression is required before completion';
  END IF;

  SELECT * INTO v_order
  FROM public.imaging_orders
  WHERE id = _imaging_order_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;
  IF v_order.status <> 'in_progress' THEN
    RAISE EXCEPTION 'Imaging order must be in progress before completion';
  END IF;

  IF v_order.encounter_id IS NOT NULL THEN
    SELECT status INTO v_encounter_status
    FROM public.encounters
    WHERE id = v_order.encounter_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
    IF v_encounter_status IN ('completed','cancelled') THEN
      RAISE EXCEPTION 'Cannot complete imaging for a completed or cancelled encounter';
    END IF;
  END IF;

  IF v_order.service_order_id IS NOT NULL THEN
    SELECT * INTO v_service
    FROM public.service_orders
    WHERE id = v_order.service_order_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Linked service order not found'; END IF;
    IF v_service.department <> 'imaging' THEN
      RAISE EXCEPTION 'Linked service order is not an imaging order';
    END IF;
    IF v_service.status <> 'in_progress' THEN
      RAISE EXCEPTION 'Linked service order must be in progress before imaging completion';
    END IF;

    UPDATE public.service_orders
    SET status = 'completed', completed_at = now(), updated_at = now()
    WHERE id = v_service.id;

    UPDATE public.department_queues
    SET status = 'completed', completed_at = now(), updated_at = now()
    WHERE service_order_id = v_service.id;
  END IF;

  UPDATE public.imaging_orders
  SET report = NULLIF(trim(COALESCE(_report,'')),''),
      impression = NULLIF(trim(COALESCE(_impression,'')),''),
      status = 'completed',
      updated_at = now()
  WHERE id = v_order.id
  RETURNING * INTO v_order;

  -- The requesting clinician is the workflow owner captured at order creation.
  -- A user-targeted notification keeps the result out of unrelated clinical queues.
  IF v_order.requested_by IS NOT NULL THEN
    INSERT INTO public.notifications (
      recipient_user_id,
      title,
      message,
      severity,
      category,
      link,
      related_patient_id,
      related_entity_id,
      metadata
    ) VALUES (
      v_order.requested_by,
      'Radiology report ready',
      format('The %s report for this patient is complete and ready for clinical review.', v_order.study_name),
      CASE WHEN lower(COALESCE(v_order.priority, 'routine')) IN ('urgent', 'stat') THEN 'warning' ELSE 'info' END,
      'other',
      '/radiology',
      v_order.patient_id,
      v_order.id,
      jsonb_build_object(
        'workflow', 'imaging_result_review',
        'imaging_order_id', v_order.id,
        'encounter_id', v_order.encounter_id,
        'service_order_id', v_order.service_order_id,
        'priority', v_order.priority
      )
    );
  END IF;

  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_imaging_order(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_imaging_order(uuid,text,text) TO authenticated;

COMMENT ON FUNCTION public.complete_imaging_order(uuid,text,text) IS
  'Completes an imaging order, synchronizes its service/department queue, and notifies the requesting clinician that the report is ready.';
