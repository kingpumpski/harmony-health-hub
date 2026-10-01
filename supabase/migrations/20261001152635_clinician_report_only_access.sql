-- Grant clinicians report viewing only; report submission/financial permissions remain separately governed.
DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.permissions
    WHERE permission_key = 'reports' AND is_active
  ) THEN
    RAISE EXCEPTION 'Active reports permission is required before assigning clinician report access';
  END IF;

  INSERT INTO public.role_permissions(role, permission_key)
  SELECT v.role::public.app_role, 'reports'
  FROM (VALUES ('practitioner'), ('lab_technician')) AS v(role)
  WHERE NOT EXISTS (
    SELECT 1 FROM public.role_permissions rp
    WHERE rp.role = v.role::public.app_role
      AND rp.permission_key = 'reports'
  );
END;
$migration$;
