CREATE OR REPLACE FUNCTION public.seed_facility_reports(_facility_id UUID)
RETURNS INTEGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_type TEXT;
  v_count INTEGER := 0;
  v_user UUID := auth.uid();
BEGIN
  IF v_user IS NULL OR NOT public.has_role(v_user, 'admin') THEN
    RAISE EXCEPTION 'Only administrators may seed facility report configuration';
  END IF;

  SELECT facility_type INTO v_type
  FROM public.healthcare_facilities
  WHERE id = _facility_id;

  IF v_type IS NULL THEN
    RAISE EXCEPTION 'Facility not found';
  END IF;

  INSERT INTO public.facility_report_config(facility_id, report_id, is_enabled)
  SELECT _facility_id, rd.id, TRUE
  FROM public.report_definitions rd
  WHERE rd.is_active AND (
    (v_type = 'chps_compound' AND rd.report_code IN ('RPT-001','RPT-003','RPT-012','RPT-019','RPT-020','RPT-032')) OR
    (v_type = 'health_centre' AND rd.report_code BETWEEN 'RPT-001' AND 'RPT-041' AND rd.report_code NOT IN ('RPT-005','RPT-006','RPT-007','RPT-008','RPT-009','RPT-011')) OR
    (v_type IN ('district_hospital','regional_hospital','teaching_hospital','specialist_clinic') AND rd.is_active) OR
    (v_type = 'hiv_clinic' AND rd.report_code IN ('RPT-005','RPT-006','RPT-007','RPT-008','RPT-009','RPT-010','RPT-011','RPT-032','RPT-033')) OR
    (v_type = 'maternity_home' AND rd.report_code IN ('RPT-012','RPT-013','RPT-015','RPT-016','RPT-017','RPT-021','RPT-022'))
  )
  ON CONFLICT (facility_id, report_id) DO UPDATE SET is_enabled = TRUE, updated_at = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.seed_facility_reports(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seed_facility_reports(UUID) TO authenticated;
