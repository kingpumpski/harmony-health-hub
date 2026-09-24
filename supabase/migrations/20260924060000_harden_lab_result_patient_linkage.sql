-- Prevent approval of a laboratory result whose patient context disagrees
-- with the linked laboratory order or its encounter context.
CREATE OR REPLACE FUNCTION public.approve_lab_result(_lab_result_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  r public.lab_results%ROWTYPE;
  o public.lab_orders%ROWTYPE;
  encounter_patient_id uuid;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'lab_technician')
    OR public.has_role(uid,'practitioner')
  ) THEN
    RAISE EXCEPTION 'Laboratory approval role required';
  END IF;

  SELECT * INTO r
  FROM public.lab_results
  WHERE id=_lab_result_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Laboratory result not found';
  END IF;

  IF r.status <> 'completed' THEN
    RAISE EXCEPTION 'Only completed results can be approved';
  END IF;

  SELECT * INTO o
  FROM public.lab_orders
  WHERE id=r.lab_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Laboratory order not found';
  END IF;

  IF o.status <> 'completed' THEN
    RAISE EXCEPTION 'Laboratory order must be completed before result approval';
  END IF;

  IF r.patient_id IS NULL OR o.patient_id IS NULL
     OR r.patient_id IS DISTINCT FROM o.patient_id THEN
    RAISE EXCEPTION 'Laboratory result and order patient context do not match';
  END IF;

  IF o.encounter_id IS NOT NULL THEN
    SELECT e.patient_id INTO encounter_patient_id
    FROM public.encounters e
    WHERE e.id=o.encounter_id;

    IF encounter_patient_id IS NULL
       OR encounter_patient_id IS DISTINCT FROM o.patient_id THEN
      RAISE EXCEPTION 'Laboratory order encounter does not belong to patient';
    END IF;
  END IF;

  UPDATE public.lab_results
  SET status='approved', approved_by=uid, approved_at=now(), updated_at=now()
  WHERE id=r.id AND status='completed';

  UPDATE public.lab_orders
  SET status='approved', updated_at=now()
  WHERE id=o.id AND status='completed';

  RETURN jsonb_build_object(
    'lab_result_id',r.id,
    'lab_order_id',o.id,
    'patient_id',r.patient_id,
    'status','approved'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.approve_lab_result(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_lab_result(uuid) TO authenticated;
