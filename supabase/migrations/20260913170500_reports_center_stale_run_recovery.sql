-- Recover abandoned Reports Center generation runs so a crashed browser/session
-- cannot permanently hold the active-run uniqueness guard.
CREATE OR REPLACE FUNCTION public.recover_stale_report_generation_run(
  _run_id UUID,
  _stale_after_minutes INTEGER DEFAULT 30
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := auth.uid();
  v_run public.report_generation_runs;
  v_stale_after INTEGER := GREATEST(COALESCE(_stale_after_minutes, 30), 5);
  v_recovered BOOLEAN := FALSE;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  SELECT * INTO v_run
  FROM public.report_generation_runs
  WHERE id = _run_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Report generation run not found';
  END IF;

  IF NOT public.has_facility_access(v_user, v_run.facility_id) THEN
    RAISE EXCEPTION 'You do not have access to this facility';
  END IF;

  IF v_run.status IN ('queued', 'processing')
     AND COALESCE(v_run.started_at, v_run.created_at) < now() - make_interval(mins => v_stale_after) THEN
    UPDATE public.report_generation_items
    SET status = 'failed',
        error_message = 'Generation run was recovered after becoming stale.',
        completed_at = now()
    WHERE run_id = v_run.id
      AND status IN ('queued', 'processing');

    UPDATE public.report_generation_runs
    SET status = 'failed',
        failed_count = GREATEST(total_reports - COALESCE(success_count, 0) - COALESCE(warning_count, 0), 0),
        completed_at = now()
    WHERE id = v_run.id;

    v_recovered := TRUE;
  END IF;

  RETURN v_recovered;
END;
$$;

REVOKE ALL ON FUNCTION public.recover_stale_report_generation_run(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.recover_stale_report_generation_run(UUID, INTEGER) TO authenticated;
