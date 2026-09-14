-- Harden Reports Center lifecycle trigger functions against mutable search_path execution.

CREATE OR REPLACE FUNCTION public.validate_report_generation_item_transition()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SET search_path = public
AS $$
BEGIN
  IF NEW.run_id <> OLD.run_id OR NEW.report_id <> OLD.report_id THEN
    RAISE EXCEPTION 'Report generation item identity cannot be changed.' USING errcode = '22000';
  END IF;
  IF OLD.status = 'queued' AND NEW.status NOT IN ('queued', 'processing', 'failed') THEN
    RAISE EXCEPTION 'Invalid report generation item transition.' USING errcode = '22000';
  END IF;
  IF OLD.status = 'processing' AND NEW.status NOT IN ('processing', 'completed', 'warning', 'failed') THEN
    RAISE EXCEPTION 'Invalid report generation item transition.' USING errcode = '22000';
  END IF;
  IF OLD.status = 'completed' AND NEW.status NOT IN ('completed', 'warning') THEN
    RAISE EXCEPTION 'Terminal report generation item state cannot be changed.' USING errcode = '22000';
  END IF;
  IF OLD.status IN ('warning', 'failed') AND NEW.status <> OLD.status THEN
    RAISE EXCEPTION 'Terminal report generation item state cannot be changed.' USING errcode = '22000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_report_generation_run_transition()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SET search_path = public
AS $$
DECLARE
  v_completed INTEGER;
  v_warning INTEGER;
  v_failed INTEGER;
  v_total INTEGER;
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
