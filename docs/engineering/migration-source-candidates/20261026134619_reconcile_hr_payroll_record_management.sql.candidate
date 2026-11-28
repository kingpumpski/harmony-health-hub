BEGIN;

ALTER TABLE public.hr_employees
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by uuid REFERENCES auth.users(id);

CREATE OR REPLACE FUNCTION public.guard_hr_employee_archive()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.archived_at IS NULL THEN
      NEW.archived_by := NULL;
    ELSE
      IF NOT (
        (SELECT public.current_user_has_role('admin'::public.app_role))
        OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
      ) THEN
        RAISE EXCEPTION 'Only administrators can create archived employee records';
      END IF;

      IF NEW.archived_at IS NOT NULL
         AND NEW.archived_by IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'The archiving user must match the authenticated user';
      END IF;
    END IF;
  ELSIF NEW.archived_at IS DISTINCT FROM OLD.archived_at
     OR NEW.archived_by IS DISTINCT FROM OLD.archived_by THEN
    IF NOT (
      (SELECT public.current_user_has_role('admin'::public.app_role))
      OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
    ) THEN
      RAISE EXCEPTION 'Only administrators can archive or restore employee records';
    END IF;

    IF NEW.archived_at IS NULL THEN
      NEW.archived_by := NULL;
    ELSIF NEW.archived_by IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'The archiving user must match the authenticated user';
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS hr_employees_record_management_guard
  ON public.hr_employees;
CREATE TRIGGER hr_employees_record_management_guard
  BEFORE INSERT OR UPDATE ON public.hr_employees
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_hr_employee_archive();

REVOKE ALL ON FUNCTION public.guard_hr_employee_archive() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.guard_payroll_period_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF NEW.facility_id IS DISTINCT FROM OLD.facility_id THEN
    RAISE EXCEPTION 'A payroll period cannot be moved to another facility';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT (OLD.status = 'draft' AND NEW.status = 'cancelled') THEN
    RAISE EXCEPTION 'Only draft payroll periods can be cancelled';
  END IF;

  IF OLD.status <> 'draft'
     AND ROW(NEW.name, NEW.period_start, NEW.period_end, NEW.pay_date)
         IS DISTINCT FROM
         ROW(OLD.name, OLD.period_start, OLD.period_end, OLD.pay_date) THEN
    RAISE EXCEPTION 'Only draft payroll periods can be edited';
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS payroll_periods_record_management_guard
  ON public.payroll_periods;
CREATE TRIGGER payroll_periods_record_management_guard
  BEFORE UPDATE ON public.payroll_periods
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_payroll_period_update();

REVOKE ALL ON FUNCTION public.guard_payroll_period_update() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.guard_payroll_item_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_period_status text;
  v_period_facility uuid;
  v_employee_facility uuid;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.payroll_period_id IS DISTINCT FROM OLD.payroll_period_id
       OR NEW.employee_id IS DISTINCT FROM OLD.employee_id THEN
      RAISE EXCEPTION 'A payroll item cannot be moved to another period or employee';
    END IF;

    IF OLD.status <> 'draft' THEN
      RAISE EXCEPTION 'Only draft payroll items can be edited';
    END IF;

    IF NEW.status NOT IN ('draft', 'void') THEN
      RAISE EXCEPTION 'Draft payroll items may only remain draft or be voided';
    END IF;

    IF NEW.status = 'void'
       AND ROW(
         NEW.basic_pay, NEW.allowances, NEW.other_earnings,
         NEW.statutory_deductions, NEW.other_deductions,
         NEW.gross_pay, NEW.net_pay, NEW.payment_reference
       ) IS DISTINCT FROM ROW(
         OLD.basic_pay, OLD.allowances, OLD.other_earnings,
         OLD.statutory_deductions, OLD.other_deductions,
         OLD.gross_pay, OLD.net_pay, OLD.payment_reference
       ) THEN
      RAISE EXCEPTION 'Void a payroll item without changing its pay values';
    END IF;
  ELSIF NEW.status <> 'draft' THEN
    RAISE EXCEPTION 'New payroll items must start in draft status';
  END IF;

  SELECT p.status, p.facility_id
  INTO v_period_status, v_period_facility
  FROM public.payroll_periods p
  WHERE p.id = NEW.payroll_period_id;

  IF v_period_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'Payroll items can only be changed while their period is draft';
  END IF;

  SELECT e.facility_id
  INTO v_employee_facility
  FROM public.hr_employees e
  WHERE e.id = NEW.employee_id;

  IF v_employee_facility IS DISTINCT FROM v_period_facility THEN
    RAISE EXCEPTION 'Payroll item employee and period must belong to the same facility';
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS payroll_items_record_management_guard
  ON public.payroll_items;
CREATE TRIGGER payroll_items_record_management_guard
  BEFORE INSERT OR UPDATE ON public.payroll_items
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_payroll_item_write();

REVOKE ALL ON FUNCTION public.guard_payroll_item_write() FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS hr_employees_deny_hard_delete
  ON public.hr_employees;
CREATE POLICY hr_employees_deny_hard_delete
  ON public.hr_employees AS RESTRICTIVE
  FOR DELETE TO authenticated
  USING (false);

DROP POLICY IF EXISTS payroll_periods_deny_hard_delete
  ON public.payroll_periods;
CREATE POLICY payroll_periods_deny_hard_delete
  ON public.payroll_periods AS RESTRICTIVE
  FOR DELETE TO authenticated
  USING (false);

DROP POLICY IF EXISTS payroll_items_deny_hard_delete
  ON public.payroll_items;
CREATE POLICY payroll_items_deny_hard_delete
  ON public.payroll_items AS RESTRICTIVE
  FOR DELETE TO authenticated
  USING (false);

CREATE OR REPLACE FUNCTION public.generate_payroll_items(_payroll_period_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_facility uuid;
  v_status text;
  v_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    (SELECT public.current_user_has_role('admin'::public.app_role))
    OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
    OR (SELECT public.current_user_has_role('accountant'::public.app_role))
  ) THEN
    RAISE EXCEPTION 'Payroll generation is not permitted for this role';
  END IF;

  SELECT p.facility_id, p.status
  INTO v_facility, v_status
  FROM public.payroll_periods p
  WHERE p.id = _payroll_period_id
  FOR UPDATE;

  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'Payroll period not found';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Payroll items can only be generated for a draft period';
  END IF;

  IF (SELECT public.current_user_has_role('accountant'::public.app_role))
     AND v_facility IS DISTINCT FROM (SELECT public.current_user_facility_id()) THEN
    RAISE EXCEPTION 'Payroll period is outside the current facility scope';
  END IF;

  INSERT INTO public.payroll_items (
    payroll_period_id, employee_id, basic_pay, allowances, other_earnings,
    statutory_deductions, other_deductions, gross_pay, net_pay
  )
  SELECT
    _payroll_period_id, e.id, e.base_salary, 0, 0, 0, 0, e.base_salary, e.base_salary
  FROM public.hr_employees e
  WHERE e.facility_id = v_facility
    AND e.employment_status = 'active'
    AND e.archived_at IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.payroll_items pi
      WHERE pi.payroll_period_id = _payroll_period_id
        AND pi.employee_id = e.id
    );

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.generate_payroll_items(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_payroll_items(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
