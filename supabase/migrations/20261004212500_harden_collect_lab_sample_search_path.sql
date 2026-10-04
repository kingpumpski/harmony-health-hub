BEGIN;

CREATE OR REPLACE FUNCTION public.collect_lab_sample(_lab_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  o public.lab_orders%ROWTYPE;
  g public.service_orders%ROWTYPE;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'lab_technician')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Laboratory clinical role required';
  END IF;

  SELECT * INTO o
  FROM public.lab_orders
  WHERE id=_lab_order_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF o.facility_id IS NULL THEN RAISE EXCEPTION 'Laboratory order facility attribution is unresolved'; END IF;

  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin'))
     AND (v_facility IS NULL OR o.facility_id IS DISTINCT FROM v_facility) THEN
    RAISE EXCEPTION 'Laboratory order belongs to a different facility context';
  END IF;

  IF o.status <> 'ordered' THEN
    RAISE EXCEPTION 'Only ordered laboratory requests can have samples collected';
  END IF;

  SELECT * INTO g
  FROM public.service_orders
  WHERE related_entity_id=o.id
    AND department='laboratory'
    AND patient_id=o.patient_id
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF g.id IS NOT NULL
     AND (g.facility_id IS NULL OR g.facility_id IS DISTINCT FROM o.facility_id) THEN
    RAISE EXCEPTION 'Laboratory payment record facility lineage is unresolved or mismatched';
  END IF;

  IF g.id IS NOT NULL AND g.status NOT IN('released','in_progress','completed') THEN
    RAISE EXCEPTION 'Payment approval required before sample collection';
  END IF;

  UPDATE public.lab_orders
  SET status='sample_collected',
      collected_by=uid,
      sample_collected_at=pg_catalog.now(),
      updated_at=pg_catalog.now()
  WHERE id=o.id;

  RETURN jsonb_build_object('lab_order_id',o.id,'status','sample_collected');
END;
$function$;

REVOKE ALL ON FUNCTION public.collect_lab_sample(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.collect_lab_sample(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.collect_lab_sample(uuid) TO authenticated;

COMMIT;