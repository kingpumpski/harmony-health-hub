-- Keep report generation and submission periods internally consistent at the database boundary.
-- The application validates YYYY-MM periods, while these constraints prevent malformed
-- date ranges from being persisted through direct or future server-side writes.

ALTER TABLE public.report_generation_runs
  ADD CONSTRAINT report_generation_runs_period_order
  CHECK (period_end >= period_start);

ALTER TABLE public.report_submissions
  ADD CONSTRAINT report_submissions_period_order
  CHECK (period_end >= period_start);

ALTER TABLE public.report_submissions
  ADD CONSTRAINT report_submissions_due_date_in_period
  CHECK (due_date >= period_start AND due_date <= period_end);
