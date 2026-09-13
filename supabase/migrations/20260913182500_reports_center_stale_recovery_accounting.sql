-- Allow the trusted stale-run recovery RPC to finalize a run that failed before
-- generation items could be inserted. Normal callers remain subject to strict
-- item/run accounting validation.

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

  -- Mark this transaction as an internal recovery operation. The generation-run
  -- transition trigger uses this only for the exceptional case where the run
  -- failed before its item rows could be created.
  PERFORM set_config('app.reports_center_stale_recovery', 'true', true);

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

CREATE OR REPLACE FUNCTION public.validate_report_generation_run_transition()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
DECLARE
  v_completed INTEGER;
  v_warning INTEGER;
  v_failed INTEGER;
  v_total INTEGER;
  v_stale_recovery BOOLEAN := COALESCE(current_setting('app.reports_center_stale_recovery', true), 'false') = 'true';
BEGIN
  IF NEW.facility_id <> OLD.facility_id
     OR NEW.period_start <> OLD.period_start
     OR NEW.period_end <> OLD.period_end
     OR NEW.frequency <> OLD.frequency
     OR NEW.total_reports <> OLD.total_reports
     OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'Report generation run identity cannot be changed.' USING errcode = '22000';
  END IF;

  IF OLD.status = 'queued' AND NEW.status NOT IN ('queued', 'processing', 'failed') THEN
    RAISE EXCEPTION 'Invalid report generation run transition.' USING errcode = '22000';
  END IF;
  IF OLD.status = 'processing' AND NEW.status NOT IN ('processing', 'completed', 'partial_failed', 'failed') THEN
    RAISE EXCEPTION 'Invalid report generation run transition.' USING errcode = '22000';
  END IF;
  IF OLD.status IN ('completed', 'partial_failed', 'failed', 'cancelled') AND NEW.status <> OLD.status THEN
    RAISE EXCEPTION 'Terminal report generation run state cannot be changed.' USING errcode = '22000';
  END IF;

  IF NEW.status IN ('completed', 'partial_failed', 'failed') THEN
    SELECT
      COUNT(*) FILTER (WHERE status = 'completed'),
      COUNT(*) FILTER (WHERE status = 'warning'),
      COUNT(*) FILTER (WHERE status = 'failed'),
      COUNT(*)
    INTO v_completed, v_warning, v_failed, v_total
    FROM public.report_generation_items
    WHERE run_id = NEW.id;

    IF v_stale_recovery
       AND NEW.status = 'failed'
       AND v_total = 0
       AND NEW.success_count = 0
       AND NEW.warning_count = 0
       AND NEW.failed_count = NEW.total_reports THEN
      RETURN NEW;
    END IF;

    IF v_total <> NEW.total_reports
       OR v_completed <> NEW.success_count
       OR v_warning <> NEW.warning_count
       OR v_failed <> NEW.failed_count
       OR NEW.success_count + NEW.warning_count + NEW.failed_count <> NEW.total_reports THEN
      RAISE EXCEPTION 'Report generation run accounting does not match its generation items.' USING errcode = '22000';
    END IF;

    IF NEW.status = 'completed' AND (NEW.failed_count <> 0 OR NEW.total_reports <> NEW.success_count + NEW.warning_count) THEN
      RAISE EXCEPTION 'A completed report generation run cannot contain failed items.' USING errcode = '22000';
    END IF;
    IF NEW.status = 'failed' AND NEW.failed_count <> NEW.total_reports THEN
      RAISE EXCEPTION 'A failed report generation run must have all items failed.' USING errcode = '22000';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_report_generation_run_transition ON public.report_generation_runs;
CREATE TRIGGER trg_validate_report_generation_run_transition
BEFORE UPDATE ON public.report_generation_runs
FOR EACH ROW EXECUTE FUNCTION public.validate_report_generation_run_transition();
