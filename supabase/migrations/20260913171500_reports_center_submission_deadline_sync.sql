-- Keep submission status authoritative in the database.
-- Pending returns whose due date has passed become overdue without relying on
-- client-side display logic. Submitted/accepted/rejected records are preserved.

CREATE OR REPLACE FUNCTION public.sync_overdue_report_submissions(
  _facility_id UUID,
  _period_start DATE,
  _period_end DATE
)
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
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF NOT public.has_facility_access(v_user, _facility_id) THEN
    RAISE EXCEPTION 'You do not have access to this facility';
  END IF;

  UPDATE public.report_submissions
  SET status = 'overdue', updated_at = now()
  WHERE facility_id = _facility_id
    AND period_start = _period_start
    AND period_end = _period_end
    AND status = 'pending'
    AND due_date < CURRENT_DATE;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_overdue_report_submissions(UUID, DATE, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_overdue_report_submissions(UUID, DATE, DATE) TO authenticated;
