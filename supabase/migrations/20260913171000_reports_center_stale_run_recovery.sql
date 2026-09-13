-- Recover interrupted Reports Center runs so a browser crash cannot permanently
-- block the facility/period through the active-run uniqueness guard.

CREATE OR REPLACE FUNCTION public.recover_stale_report_run(
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
  v_cutoff TIMESTAMPTZ;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication is required';
  END IF;

  IF _stale_after_minutes < 1 OR _stale_after_minutes > 1440 THEN
    RAISE EXCEPTION 'stale_after_minutes must be between 1 and 1440';
  END IF;

  SELECT *
    INTO v_run
  FROM public.report_generation_runs
  WHERE id = _run_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF NOT public.has_facility_access(v_user, v_run.facility_id) THEN
    RAISE EXCEPTION 'You do not have access to this facility';
  END IF;

  IF v_run.status NOT IN ('queued', 'processing') THEN
    RETURN FALSE;
  END IF;

  v_cutoff := now() - make_interval(mins => _stale_after_minutes);

  IF COALESCE(v_run.started_at, v_run.created_at) > v_cutoff THEN
    RETURN FALSE;
  END IF;

  UPDATE public.report_generation_items
  SET status = 'failed',
      error_message = 'Generation run recovered after becoming stale.',
      completed_at = now()
  WHERE run_id = v_run.id
    AND status IN ('queued', 'processing');

  UPDATE public.report_generation_runs
  SET status = 'failed',
      failed_count = GREATEST(total_reports - COALESCE(success_count, 0) - COALESCE(warning_count, 0), 0),
      completed_at = now()
  WHERE id = v_run.id;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.recover_stale_report_run(UUID, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.recover_stale_report_run(UUID, INTEGER) TO authenticated;
