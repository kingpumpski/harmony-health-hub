-- Reconcile imaging lifecycle so department status and report completion are
-- server-authoritative and cannot be bypassed by direct table updates.

CREATE OR REPLACE FUNCTION public.start_imaging_order(_imaging_order_id uuid)
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
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'radiologist')) THEN
    RAISE EXCEPTION 'Clinical staff required';
  END IF;

  SELECT * INTO v_order FROM public.imaging_orders WHERE id=_imaging_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;

  IF v_order.encounter_id IS NOT NULL THEN
    SELECT status INTO v_encounter_status FROM public.encounters WHERE id=v_order.encounter_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
    IF v_encounter_status IN ('completed','cancelled') THEN
      RAISE EXCEPTION 'Cannot start imaging for a completed or cancelled encounter';
    END IF;
  END IF;

  IF v_order.status <> 'released' THEN
    RAISE EXCEPTION 'Imaging order must be released before it can start';
  END IF;

  IF v_order.service_order_id IS NULL THEN
    UPDATE public.imaging_orders
    SET status='in_progress', performed_by=auth.uid(), updated_at=now()
    WHERE id=v_order.id
    RETURNING * INTO v_order;
    RETURN v_order;
  END IF;

  SELECT * INTO v_service FROM public.service_orders WHERE id=v_order.service_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Linked service order not found'; END IF;
  IF v_service.department <> 'imaging' THEN RAISE EXCEPTION 'Linked service order is not an imaging order'; END IF;
  IF v_service.status <> 'released' THEN RAISE EXCEPTION 'Linked service order must be released before imaging can start'; END IF;

  UPDATE public.service_orders
  SET status='in_progress', started_at=COALESCE(started_at,now()), updated_at=now()
  WHERE id=v_service.id;

  UPDATE public.department_queues
  SET status='claimed', claimed_by=auth.uid(), assigned_to=auth.uid(), claimed_at=COALESCE(claimed_at,now()), updated_at=now()
  WHERE service_order_id=v_service.id;

  UPDATE public.imaging_orders
  SET status='in_progress', performed_by=auth.uid(), updated_at=now()
  WHERE id=v_order.id
  RETURNING * INTO v_order;

  RETURN v_order;
END;
$$;

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
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'radiologist')) THEN
    RAISE EXCEPTION 'Clinical staff required';
  END IF;
  IF NULLIF(trim(COALESCE(_report,'')),'') IS NULL
     AND NULLIF(trim(COALESCE(_impression,'')),'') IS NULL THEN
    RAISE EXCEPTION 'A report or impression is required before completion';
  END IF;

  SELECT * INTO v_order FROM public.imaging_orders WHERE id=_imaging_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;
  IF v_order.status <> 'in_progress' THEN RAISE EXCEPTION 'Imaging order must be in progress before completion'; END IF;

  IF v_order.encounter_id IS NOT NULL THEN
    SELECT status INTO v_encounter_status FROM public.encounters WHERE id=v_order.encounter_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
    IF v_encounter_status IN ('completed','cancelled') THEN
      RAISE EXCEPTION 'Cannot complete imaging for a completed or cancelled encounter';
    END IF;
  END IF;

  IF v_order.service_order_id IS NOT NULL THEN
    SELECT * INTO v_service FROM public.service_orders WHERE id=v_order.service_order_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Linked service order not found'; END IF;
    IF v_service.department <> 'imaging' THEN RAISE EXCEPTION 'Linked service order is not an imaging order'; END IF;
    IF v_service.status <> 'in_progress' THEN RAISE EXCEPTION 'Linked service order must be in progress before imaging completion'; END IF;

    UPDATE public.service_orders
    SET status='completed', completed_at=now(), updated_at=now()
    WHERE id=v_service.id;

    UPDATE public.department_queues
    SET status='completed', completed_at=now(), updated_at=now()
    WHERE service_order_id=v_service.id;
  END IF;

  UPDATE public.imaging_orders
  SET report=NULLIF(trim(COALESCE(_report,'')),''),
      impression=NULLIF(trim(COALESCE(_impression,'')),''),
      status='completed',
      updated_at=now()
  WHERE id=v_order.id
  RETURNING * INTO v_order;

  RETURN v_order;
END;
$$;

REVOKE ALL ON FUNCTION public.start_imaging_order(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.complete_imaging_order(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_imaging_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_imaging_order(uuid,text,text) TO authenticated;

REVOKE UPDATE, DELETE ON TABLE public.imaging_orders FROM authenticated;

COMMENT ON FUNCTION public.start_imaging_order(uuid) IS
  'Starts a released imaging order and synchronizes its linked imaging service order and queue.';
COMMENT ON FUNCTION public.complete_imaging_order(uuid,text,text) IS
  'Completes an in-progress imaging order with a report/impression and synchronizes its service order and queue.';
