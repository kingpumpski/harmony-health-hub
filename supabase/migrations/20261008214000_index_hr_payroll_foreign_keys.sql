-- Performance hardening for newly introduced HR/payroll foreign keys.
-- Indexing FK columns keeps joins and parent-row checks efficient without changing access semantics.
BEGIN;

CREATE INDEX IF NOT EXISTS idx_hr_employees_created_by
  ON public.hr_employees(created_by);

CREATE INDEX IF NOT EXISTS idx_hr_employees_profile_id
  ON public.hr_employees(profile_id);

CREATE INDEX IF NOT EXISTS idx_payroll_items_employee_id
  ON public.payroll_items(employee_id);

CREATE INDEX IF NOT EXISTS idx_payroll_periods_created_by
  ON public.payroll_periods(created_by);

COMMIT;