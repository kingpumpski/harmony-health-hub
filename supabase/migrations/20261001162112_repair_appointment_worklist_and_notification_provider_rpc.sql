-- Repair the appointment worklist function-resolution error and remove the ambiguous
-- legacy notification-provider overload. The live database version is 20261001162112.

DROP FUNCTION IF EXISTS public.set_facility_notification_provider(uuid, text, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.get_appointment_worklist(_limit integer DEFAULT 300)
RETURNS TABLE(
  id uuid,
  patient_id uuid,
  patient_code text,
  patient_first_name text,
  patient_last_name text,
  scheduled_at timestamptz,
  consultation_type text,
  practitioner_id uuid,
  practitioner_name text,
  department text,
  reason text,
  status text,
  attending_officer_id uuid,
  treatment_status text,
  treatment_notes text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_limit integer := greatest(1, least(coalesce(_limit,300),500));
  v_user uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_cross_facility boolean := public.has_role(v_user,'admin'::public.app_role)
    OR public.has_role(v_user,'it_admin'::public.app_role)
    OR public.current_user_has_role('system_superuser');
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(v_user,'admin'::public.app_role)
    OR public.has_role(v_user,'it_admin'::public.app_role)
    OR public.has_role(v_user,'system_superuser'::public.app_role)
    OR public.has_role(v_user,'practitioner'::public.app_role)
    OR public.has_role(v_user,'nurse'::public.app_role)
    OR public.has_role(v_user,'midwife'::public.app_role)
    OR public.has_role(v_user,'specialist_nurse'::public.app_role)
    OR public.has_role(v_user,'front_desk'::public.app_role)
  ) THEN RAISE EXCEPTION 'Appointment worklist access denied'; END IF;
  IF NOT v_cross_facility AND v_facility IS NULL THEN RAISE EXCEPTION 'An active facility is required to access the appointment worklist'; END IF;
  RETURN QUERY
  SELECT a.id,a.patient_id,p.patient_code,p.first_name,p.last_name,a.scheduled_at,
    COALESCE(a.consultation_type,'General Consultation'),a.practitioner_id,
    NULLIF(pg_catalog.btrim(pg_catalog.concat_ws(' ',pr.first_name,pr.last_name)),'') ,
    a.department,a.reason,a.status,a.attending_officer_id,a.treatment_status,a.treatment_notes
  FROM public.appointments a
  JOIN public.patients p ON p.id=a.patient_id
  LEFT JOIN public.profiles pr ON pr.id=a.practitioner_id
  WHERE COALESCE(p.status,'active') <> 'inactive'
    AND (v_cross_facility OR (a.facility_id=v_facility AND p.facility_id=v_facility))
  ORDER BY a.scheduled_at ASC
  LIMIT v_limit;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.set_facility_notification_provider(uuid,text,text,text,text,text,text,jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.set_facility_notification_provider(uuid,text,text,text,text,text,text,jsonb) FROM anon;
