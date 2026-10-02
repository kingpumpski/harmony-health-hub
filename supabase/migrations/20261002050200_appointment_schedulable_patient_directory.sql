-- Appointment scheduling must only offer active patients with verified facility lineage.
-- This is deliberately separate from the general patient directory: a patient without
-- facility attribution cannot safely enter the appointment workflow.

CREATE OR REPLACE FUNCTION public.get_appointment_schedulable_patients(_limit integer DEFAULT 300)
RETURNS TABLE (
  id uuid,
  patient_code text,
  first_name text,
  last_name text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_cross_facility boolean;
  v_limit integer := greatest(1, least(coalesce(_limit, 300), 500));
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(v_user, 'admin'::public.app_role)
    OR public.has_role(v_user, 'it_admin'::public.app_role)
    OR public.has_role(v_user, 'practitioner'::public.app_role)
    OR public.has_role(v_user, 'nurse'::public.app_role)
    OR public.has_role(v_user, 'midwife'::public.app_role)
    OR public.has_role(v_user, 'specialist_nurse'::public.app_role)
    OR public.has_role(v_user, 'front_desk'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Not authorized to schedule appointments';
  END IF;

  v_cross_facility :=
    public.has_role(v_user, 'admin'::public.app_role)
    OR public.has_role(v_user, 'it_admin'::public.app_role);

  IF NOT v_cross_facility AND v_facility IS NULL THEN
    RAISE EXCEPTION 'An active facility is required to schedule appointments';
  END IF;

  RETURN QUERY
  SELECT p.id, p.patient_code, p.first_name, p.last_name
  FROM public.patients p
  WHERE coalesce(p.status, 'active') <> 'inactive'
    AND p.facility_id IS NOT NULL
    AND (v_cross_facility OR p.facility_id = v_facility)
  ORDER BY p.created_at DESC
  LIMIT v_limit;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_appointment_schedulable_patients(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_appointment_schedulable_patients(integer) TO authenticated;
