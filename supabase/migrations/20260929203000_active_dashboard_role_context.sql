-- Validate the active operational dashboard role against authoritative user_roles.
-- The existing no-argument function remains the primary-role compatibility contract.
DO $outer$
DECLARE
  v_sql text;
BEGIN
  SELECT pg_get_functiondef('public.get_role_dashboard_summary()'::regprocedure) INTO v_sql;
  v_sql := replace(
    v_sql,
    'CREATE OR REPLACE FUNCTION public.get_role_dashboard_summary()',
    'CREATE OR REPLACE FUNCTION public.get_role_dashboard_summary_for_role(_requested_role text DEFAULT NULL)'
  );
  v_sql := replace(
    v_sql,
    $old$  SELECT ur.role::text INTO v_role
  FROM public.user_roles ur
  WHERE ur.user_id = v_uid
    AND ur.role IN ('admin','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','radiology_technician','pharmacist','accountant','front_desk','canteen','patient','it_admin')
  ORDER BY ur.created_at ASC, ur.role::text ASC
  LIMIT 1;$old$,
    $new$  IF _requested_role IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.user_roles ur
      WHERE ur.user_id = v_uid
        AND ur.role::text = _requested_role
        AND ur.role IN ('admin','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','radiology_technician','pharmacist','accountant','front_desk','canteen','patient','it_admin')
    ) THEN
      RAISE EXCEPTION 'Requested dashboard role is not assigned to the authenticated user';
    END IF;
    v_role := _requested_role;
  ELSE
    SELECT ur.role::text INTO v_role
    FROM public.user_roles ur
    WHERE ur.user_id = v_uid
      AND ur.role IN ('admin','practitioner','nurse','midwife','specialist_nurse','lab_technician','radiologist','radiology_technician','pharmacist','accountant','front_desk','canteen','patient','it_admin')
    ORDER BY ur.created_at ASC, ur.role::text ASC
    LIMIT 1;
  END IF;$new$
  );
  EXECUTE v_sql;
END $outer$;

REVOKE ALL ON FUNCTION public.get_role_dashboard_summary_for_role(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_role_dashboard_summary_for_role(text) TO authenticated;
NOTIFY pgrst, 'reload schema';