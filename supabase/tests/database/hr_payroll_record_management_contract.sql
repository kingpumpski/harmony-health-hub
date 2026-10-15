begin;

select plan(9);

select has_column(
  'public',
  'hr_employees',
  'archived_at',
  'employee records must support audit-preserving archive'
);

select has_column(
  'public',
  'hr_employees',
  'archived_by',
  'employee archival must record the responsible user'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.hr_employees'::regclass
      and tgname = 'hr_employees_record_management_guard'
      and not tgisinternal
  ),
  'employee archive and update guard must be installed'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.payroll_periods'::regclass
      and tgname = 'payroll_periods_record_management_guard'
      and not tgisinternal
  ),
  'payroll period lifecycle guard must be installed'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgrelid = 'public.payroll_items'::regclass
      and tgname = 'payroll_items_record_management_guard'
      and not tgisinternal
  ),
  'payroll item calculation and lifecycle guard must be installed'
);

select ok(
  exists (
    select 1 from pg_policy
    where polrelid = 'public.hr_employees'::regclass
      and polname = 'hr_employees_deny_hard_delete'
      and polpermissive = false
  ),
  'employee records must use archive rather than hard delete'
);

select ok(
  exists (
    select 1 from pg_policy
    where polrelid = 'public.payroll_periods'::regclass
      and polname = 'payroll_periods_deny_hard_delete'
      and polpermissive = false
  ),
  'payroll periods must use status transitions rather than hard delete'
);

select ok(
  exists (
    select 1 from pg_policy
    where polrelid = 'public.payroll_items'::regclass
      and polname = 'payroll_items_deny_hard_delete'
      and polpermissive = false
  ),
  'payroll items must use void status rather than hard delete'
);

select ok(
  to_regprocedure('public.generate_payroll_items(uuid)') is not null,
  'payroll generation must remain available through its authorized database function'
);

select * from finish();
rollback;
