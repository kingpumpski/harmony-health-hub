-- Prevent concurrent duplicate generation runs for the same facility/period.
-- Completed historical runs remain repeatable; only queued/processing runs are
-- mutually exclusive so a double-click or concurrent client cannot create two
-- active runs for the same reporting period.

CREATE UNIQUE INDEX IF NOT EXISTS uq_report_generation_active_run
ON public.report_generation_runs (facility_id, period_start, period_end, frequency)
WHERE status IN ('queued', 'processing');
