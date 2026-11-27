-- Facility-scope the department queue RPC.
-- Facility admins may troubleshoot queues within their own facility, but only
-- explicit platform roles may bypass the active-facility boundary.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_department_queue(
  _department text,
  _limit integer DEFAULT 100
)
RETURNS TABLE(
  id uuid, department text, status text, queued_at timestamptz, service_order_id uuid,
  service_name text, amount numeric, service_order_status text, patient_id uuid,
  patient_first_name text, patient_last_name text, patient_code text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_department text := NULLIF(pg_catalog.btrim(_department), '');
  v_department_key text;
  v_facility uuid := public.current_user_facility_id();
  v_platform_admin boolean :=
    public.has_role(auth.uid(), 'it_admin')
    OR public.has_role(auth.uid(), 'system_superuser');
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_department IS NULL THEN RETURN; END IF;
  IF _limit IS NULL OR _limit < 1 OR _limit > 500 THEN RAISE EXCEPTION 'Invalid queue limit'; END IF;
  IF v_facility IS NULL AND NOT v_platform_admin THEN
    RAISE EXCEPTION 'An active facility is required for department queue access';
  END IF;

  v_department_key := pg_catalog.lower(pg_catalog.regexp_replace(v_department, '[[:space:]_-]+', ' ', 'g'));

  -- Facility admins retain departmental troubleshooting access, but are not
  -- platform-wide readers. Non-admin operational users must still match both
  -- the department role and their canonical profile department.
  IF NOT (
    public.has_role(auth.uid(), 'admin')
    OR v_platform_admin
  ) THEN
    IF v_department_key IN ('laboratory', 'lab', 'pathology') THEN
      IF NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role='lab_technician') THEN
        RAISE EXCEPTION 'Department queue access denied for laboratory role';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
        AND pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(p.department,''), '[[:space:]_-]+', ' ', 'g')) IN ('laboratory','lab','pathology')) THEN
        RAISE EXCEPTION 'Department queue access denied for this department';
      END IF;
    ELSIF v_department_key IN ('radiology', 'imaging') THEN
      IF NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role IN ('radiologist','radiology_technician')) THEN
        RAISE EXCEPTION 'Department queue access denied for imaging role';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
        AND pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(p.department,''), '[[:space:]_-]+', ' ', 'g')) IN ('radiology','imaging')) THEN
        RAISE EXCEPTION 'Department queue access denied for this department';
      END IF;
    ELSIF v_department_key IN ('pharmacy', 'dispensary') THEN
      IF NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role='pharmacist') THEN
        RAISE EXCEPTION 'Department queue access denied for pharmacy role';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
        AND pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(p.department,''), '[[:space:]_-]+', ' ', 'g')) IN ('pharmacy','dispensary')) THEN
        RAISE EXCEPTION 'Department queue access denied for this department';
      END IF;
    ELSIF v_department_key IN ('accounts', 'accounting', 'finance') THEN
      IF NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role='accountant') THEN
        RAISE EXCEPTION 'Department queue access denied for accounts role';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
        AND pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(p.department,''), '[[:space:]_-]+', ' ', 'g')) IN ('accounts','accounting','finance')) THEN
        RAISE EXCEPTION 'Department queue access denied for this department';
      END IF;
    ELSIF v_department_key IN ('canteen', 'dietary') THEN
      IF NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role='canteen') THEN
        RAISE EXCEPTION 'Department queue access denied for canteen role';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
        AND pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(p.department,''), '[[:space:]_-]+', ' ', 'g')) IN ('canteen','dietary')) THEN
        RAISE EXCEPTION 'Department queue access denied for this department';
      END IF;
    ELSIF v_department_key IN ('front desk', 'reception') THEN
      IF NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role='front_desk') THEN
        RAISE EXCEPTION 'Department queue access denied for front desk role';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
        AND pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(p.department,''), '[[:space:]_-]+', ' ', 'g')) IN ('front desk','reception')) THEN
        RAISE EXCEPTION 'Department queue access denied for this department';
      END IF;
    ELSIF v_department_key IN ('nursing', 'inpatient') THEN
      IF NOT EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role IN ('nurse','specialist_nurse','midwife')) THEN
        RAISE EXCEPTION 'Department queue access denied for nursing role';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid()
        AND pg_catalog.lower(pg_catalog.regexp_replace(COALESCE(p.department,''), '[[:space:]_-]+', ' ', 'g')) IN ('nursing','inpatient')) THEN
        RAISE EXCEPTION 'Department queue access denied for this department';
      END IF;
    ELSE
      RAISE EXCEPTION 'Department queue is not an operational role queue';
    END IF;
  END IF;

  RETURN QUERY
  SELECT q.id,q.department,q.status,q.queued_at,q.service_order_id,so.service_name,so.amount,
         so.status,so.patient_id,p.first_name,p.last_name,p.patient_code
  FROM public.department_queues q
  JOIN public.service_orders so ON so.id=q.service_order_id
  JOIN public.patients p ON p.id=so.patient_id
  WHERE pg_catalog.lower(pg_catalog.regexp_replace(q.department, '[[:space:]_-]+', ' ', 'g')) = v_department_key
    AND q.status IN ('queued','claimed')
    AND (
      v_platform_admin
      OR (
        q.facility_id = v_facility
        AND so.facility_id = v_facility
        AND p.facility_id = v_facility
      )
    )
  ORDER BY q.queued_at ASC
  LIMIT _limit;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_department_queue(text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_department_queue(text,integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;
