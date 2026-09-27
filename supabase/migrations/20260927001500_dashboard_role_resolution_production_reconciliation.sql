-- Reconcile the deployed role-dashboard RPC with the deterministic frontend role contract.
DO $migration$
DECLARE
  v_definition text;
  v_old text := $old$
  SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=v_uid ORDER BY ur.created_at DESC LIMIT 1;
$old$;
  v_new text := $new$
  SELECT ur.role::text INTO v_role
  FROM public.user_roles ur
  WHERE ur.user_id = v_uid
    AND ur.role IN ('admin','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','radiology_technician','pharmacist','accountant','front_desk','canteen','patient','it_admin')
  ORDER BY ur.created_at ASC, ur.role::text ASC
  LIMIT 1;
$new$;
BEGIN
  SELECT pg_get_functiondef('public.get_role_dashboard_summary()'::regprocedure) INTO v_definition;
  IF position(v_old IN v_definition) = 0 THEN
    IF position(v_new IN v_definition) > 0 THEN
      RETURN;
    END IF;
    RAISE EXCEPTION 'Expected legacy role-resolution contract was not found';
  END IF;
  v_definition := replace(v_definition, v_old, v_new);
  EXECUTE v_definition;
END
$migration$;

REVOKE ALL ON FUNCTION public.get_role_dashboard_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary() TO authenticated;
NOTIFY pgrst, 'reload schema';