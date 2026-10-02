-- Keep system superuser patient access scoped to the facility they explicitly selected.
CREATE OR REPLACE FUNCTION public.assert_patient_facility_read_context(_patient_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  patient_facility uuid;
  active_facility uuid := public.current_user_facility_id();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _patient_id IS NULL THEN RAISE EXCEPTION 'Patient is required'; END IF;

  SELECT p.facility_id INTO patient_facility
  FROM public.patients p
  WHERE p.id = _patient_id AND coalesce(p.status,'active') <> 'inactive';

  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
  IF patient_facility IS NULL THEN RAISE EXCEPTION 'Patient facility attribution is unresolved'; END IF;

  -- Facility administrators retain their existing cross-facility read permission.
  -- System superusers do not bypass this boundary: their selected context is enforced below.
  IF public.has_role(uid,'admin'::public.app_role)
     OR public.has_role(uid,'it_admin'::public.app_role) THEN
    RETURN patient_facility;
  END IF;

  IF active_facility IS NULL THEN RAISE EXCEPTION 'Active facility context is required'; END IF;
  IF patient_facility IS DISTINCT FROM active_facility THEN
    RAISE EXCEPTION 'Patient belongs to a different facility context';
  END IF;

  RETURN patient_facility;
END;
$function$;
REVOKE ALL ON FUNCTION public.assert_patient_facility_read_context(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assert_patient_facility_read_context(uuid) TO authenticated;
