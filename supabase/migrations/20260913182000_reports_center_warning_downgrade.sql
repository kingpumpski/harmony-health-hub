-- A generated item can become a warning after successful extraction when its
-- submission-tracking side effect cannot be initialized. Keep that explicit
-- operational downgrade valid while preserving all other terminal-state guards.

CREATE OR REPLACE FUNCTION public.validate_report_generation_item_transition()
RETURNS TRIGGER
LANGUAGE PLPGSQL
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
