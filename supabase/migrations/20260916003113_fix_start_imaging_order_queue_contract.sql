-- Reconcile the imaging start RPC with the canonical department_queues schema.
-- department_queues has no claimed_at column; claiming is represented by status,
-- claimed_by and assigned_to.
CREATE OR REPLACE FUNCTION public.start_imaging_order(_imaging_order_id uuid)
RETURNS public.imaging_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v public.imaging_orders%ROWTYPE;
BEGIN
  UPDATE public.imaging_orders
  SET status='in_progress',
      started_at=COALESCE(started_at, now()),
      updated_at=now()
  WHERE id=_imaging_order_id
  RETURNING * INTO v;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Imaging order not found';
  END IF;

  UPDATE public.department_queues
  SET status='claimed',
      claimed_by=auth.uid(),
      assigned_to=auth.uid(),
      updated_at=now()
  WHERE service_order_id=v.service_order_id;

  RETURN v;
END;
$function$;

REVOKE ALL ON FUNCTION public.start_imaging_order(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.start_imaging_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_imaging_order(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
