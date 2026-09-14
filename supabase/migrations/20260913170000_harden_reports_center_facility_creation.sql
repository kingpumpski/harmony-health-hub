-- Keep facility setup atomic: facility creation, creator membership and report
-- activation must succeed or fail together. This avoids orphan facilities when
-- report seeding fails after the facility row has already been committed.

CREATE OR REPLACE FUNCTION public.create_reports_facility(
  _name TEXT,
  _facility_code TEXT DEFAULT NULL,
  _facility_type TEXT DEFAULT 'district_hospital',
  _district TEXT DEFAULT NULL,
  _region TEXT DEFAULT NULL,
  _dhims2_uid TEXT DEFAULT NULL
)
RETURNS public.healthcare_facilities
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_facility public.healthcare_facilities;
BEGIN
  IF v_user IS NULL OR NOT public.has_role(v_user, 'admin') THEN
    RAISE EXCEPTION 'Only administrators may create healthcare facilities';
  END IF;

  IF NULLIF(trim(_name), '') IS NULL THEN
    RAISE EXCEPTION 'Facility name is required';
  END IF;

  INSERT INTO public.healthcare_facilities (
    name, facility_code, facility_type, district, region, dhims2_uid, created_by
  )
  VALUES (
    trim(_name), NULLIF(trim(_facility_code), ''), _facility_type,
    NULLIF(trim(_district), ''), NULLIF(trim(_region), ''),
    NULLIF(trim(_dhims2_uid), ''), v_user
  )
  RETURNING * INTO v_facility;

  INSERT INTO public.facility_memberships (facility_id, user_id, access_scope, is_active)
  VALUES (v_facility.id, v_user, 'facility', TRUE)
  ON CONFLICT (facility_id, user_id)
  DO UPDATE SET is_active = TRUE, access_scope = EXCLUDED.access_scope;

  PERFORM public.seed_facility_reports(v_facility.id);

  RETURN v_facility;
END;
$$;

REVOKE ALL ON FUNCTION public.create_reports_facility(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_reports_facility(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
