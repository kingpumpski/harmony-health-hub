-- HR and payroll foundation: facility-scoped workforce records and controlled payroll periods.
BEGIN;

CREATE TABLE IF NOT EXISTS public.hr_employees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id uuid NOT NULL REFERENCES public.healthcare_facilities(id),
  profile_id uuid NULL REFERENCES public.profiles(id),
  employee_number text NOT NULL,
  first_name text NOT NULL,
  last_name text NOT NULL,
  email text NULL,
  phone text NULL,
  department text NULL,
  job_title text NOT NULL,
  employment_type text NOT NULL DEFAULT 'full_time' CHECK (employment_type IN ('full_time','part_time','contract','casual','intern')),
  employment_status text NOT NULL DEFAULT 'active' CHECK (employment_status IN ('active','on_leave','suspended','terminated')),
  start_date date NOT NULL,
  end_date date NULL,
  base_salary numeric(14,2) NOT NULL DEFAULT 0 CHECK (base_salary >= 0),
  pay_frequency text NOT NULL DEFAULT 'monthly' CHECK (pay_frequency IN ('monthly','biweekly','weekly')),
  tax_identifier text NULL,
  ssnit_number text NULL,
  bank_name text NULL,
  bank_account_name text NULL,
  bank_account_number text NULL,
  created_by uuid NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (facility_id, employee_number)
);

CREATE TABLE IF NOT EXISTS public.payroll_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id uuid NOT NULL REFERENCES public.healthcare_facilities(id),
  name text NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  pay_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','processing','finalized','paid','cancelled')),
  created_by uuid NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (period_end >= period_start),
  UNIQUE (facility_id, period_start, period_end)
);

CREATE TABLE IF NOT EXISTS public.payroll_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_period_id uuid NOT NULL REFERENCES public.payroll_periods(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES public.hr_employees(id),
  basic_pay numeric(14,2) NOT NULL DEFAULT 0,
  allowances numeric(14,2) NOT NULL DEFAULT 0,
  other_earnings numeric(14,2) NOT NULL DEFAULT 0,
  statutory_deductions numeric(14,2) NOT NULL DEFAULT 0,
  other_deductions numeric(14,2) NOT NULL DEFAULT 0,
  gross_pay numeric(14,2) NOT NULL DEFAULT 0,
  net_pay numeric(14,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','approved','paid','void')),
  payment_reference text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (payroll_period_id, employee_id),
  CHECK (basic_pay >= 0 AND allowances >= 0 AND other_earnings >= 0 AND statutory_deductions >= 0 AND other_deductions >= 0),
  CHECK (gross_pay = basic_pay + allowances + other_earnings),
  CHECK (net_pay = greatest(0, gross_pay - statutory_deductions - other_deductions))
);

CREATE INDEX IF NOT EXISTS idx_hr_employees_facility_status ON public.hr_employees(facility_id, employment_status);
CREATE INDEX IF NOT EXISTS idx_payroll_periods_facility_dates ON public.payroll_periods(facility_id, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_payroll_items_period ON public.payroll_items(payroll_period_id);

ALTER TABLE public.hr_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS hr_employees_admin_it_accountant_select ON public.hr_employees;
DROP POLICY IF EXISTS hr_employees_admin_it_accountant_insert ON public.hr_employees;
DROP POLICY IF EXISTS hr_employees_admin_it_accountant_update ON public.hr_employees;
DROP POLICY IF EXISTS hr_employees_admin_it_accountant_delete ON public.hr_employees;
DROP POLICY IF EXISTS payroll_periods_admin_it_accountant_select ON public.payroll_periods;
DROP POLICY IF EXISTS payroll_periods_admin_it_accountant_write ON public.payroll_periods;
DROP POLICY IF EXISTS payroll_items_admin_it_accountant_select ON public.payroll_items;
DROP POLICY IF EXISTS payroll_items_admin_it_accountant_write ON public.payroll_items;

CREATE POLICY hr_employees_admin_it_accountant_select ON public.hr_employees FOR SELECT TO authenticated
USING ((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role)) OR ((select public.current_user_has_role('accountant'::public.app_role)) AND facility_id = (select public.current_user_facility_id())));
CREATE POLICY hr_employees_admin_it_accountant_insert ON public.hr_employees FOR INSERT TO authenticated
WITH CHECK (((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role))) OR ((select public.current_user_has_role('accountant'::public.app_role)) AND facility_id = (select public.current_user_facility_id())));
CREATE POLICY hr_employees_admin_it_accountant_update ON public.hr_employees FOR UPDATE TO authenticated
USING ((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role)) OR ((select public.current_user_has_role('accountant'::public.app_role)) AND facility_id = (select public.current_user_facility_id())))
WITH CHECK ((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role)) OR ((select public.current_user_has_role('accountant'::public.app_role)) AND facility_id = (select public.current_user_facility_id())));
CREATE POLICY hr_employees_admin_it_accountant_delete ON public.hr_employees FOR DELETE TO authenticated
USING ((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role)));

CREATE POLICY payroll_periods_admin_it_accountant_select ON public.payroll_periods FOR SELECT TO authenticated
USING ((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role)) OR ((select public.current_user_has_role('accountant'::public.app_role)) AND facility_id = (select public.current_user_facility_id())));
CREATE POLICY payroll_periods_admin_it_accountant_write ON public.payroll_periods FOR ALL TO authenticated
USING ((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role)) OR ((select public.current_user_has_role('accountant'::public.app_role)) AND facility_id = (select public.current_user_facility_id())))
WITH CHECK ((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role)) OR ((select public.current_user_has_role('accountant'::public.app_role)) AND facility_id = (select public.current_user_facility_id())));

CREATE POLICY payroll_items_admin_it_accountant_select ON public.payroll_items FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.payroll_periods p WHERE p.id = payroll_period_id AND ((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role)) OR ((select public.current_user_has_role('accountant'::public.app_role)) AND p.facility_id = (select public.current_user_facility_id())))));
CREATE POLICY payroll_items_admin_it_accountant_write ON public.payroll_items FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.payroll_periods p WHERE p.id = payroll_period_id AND ((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role)) OR ((select public.current_user_has_role('accountant'::public.app_role)) AND p.facility_id = (select public.current_user_facility_id())))))
WITH CHECK (EXISTS (SELECT 1 FROM public.payroll_periods p WHERE p.id = payroll_period_id AND ((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role)) OR ((select public.current_user_has_role('accountant'::public.app_role)) AND p.facility_id = (select public.current_user_facility_id())))));

CREATE OR REPLACE FUNCTION public.generate_payroll_items(_payroll_period_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_facility uuid; v_count integer;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT ((select public.current_user_has_role('admin'::public.app_role)) OR (select public.current_user_has_role('it_admin'::public.app_role)) OR (select public.current_user_has_role('accountant'::public.app_role))) THEN RAISE EXCEPTION 'Payroll generation is not permitted for this role'; END IF;
  SELECT facility_id INTO v_facility FROM public.payroll_periods WHERE id = _payroll_period_id;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Payroll period not found'; END IF;
  IF (select public.current_user_has_role('accountant'::public.app_role)) AND NOT (v_facility = (select public.current_user_facility_id())) THEN RAISE EXCEPTION 'Payroll period is outside the current facility scope'; END IF;
  INSERT INTO public.payroll_items (payroll_period_id, employee_id, basic_pay, allowances, other_earnings, statutory_deductions, other_deductions, gross_pay, net_pay)
  SELECT _payroll_period_id, e.id, e.base_salary, 0, 0, 0, 0, e.base_salary, e.base_salary
  FROM public.hr_employees e
  WHERE e.facility_id = v_facility AND e.employment_status = 'active'
    AND NOT EXISTS (SELECT 1 FROM public.payroll_items pi WHERE pi.payroll_period_id = _payroll_period_id AND pi.employee_id = e.id);
  GET DIAGNOSTICS v_count = ROW_COUNT; RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.generate_payroll_items(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_payroll_items(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;