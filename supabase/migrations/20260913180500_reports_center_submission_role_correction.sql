-- Correct the Reports Center submission role boundary to use the project's
-- established application roles. The prior migration referenced a non-existent
-- health_information role, which would make the function fail at execution time.

CREATE OR REPLACE FUNCTION public.mark_report_submissions_submitted(_submission_ids UUID[])
RETURNS INTEGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_updated INTEGER := 0;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication is required.' USING errcode = '42501';
  END IF;

  IF NOT (
    public.has_role(v_user, 'admin')
    OR public.has_role(v_user, 'practitioner')
    OR public.has_role(v_user, 'nurse')
    OR public.has_role(v_user, 'midwife')
    OR public.has_role(v_user, 'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'You are not authorized to submit reports.' USING errcode = '42501';
  END IF;

  UPDATE public.report_submissions AS rs
  SET
    status = 'submitted',
    submitted_at = now(),
    submitted_by = v_user,
    updated_at = now()
  WHERE rs.id = ANY(COALESCE(_submission_ids, '{}'::UUID[]))
    AND rs.status IN ('pending', 'overdue')
    AND public.has_facility_access(v_user, rs.facility_id);

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_report_submissions_submitted(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_report_submissions_submitted(UUID[]) TO authenticated;
