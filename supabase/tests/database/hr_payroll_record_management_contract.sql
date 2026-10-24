begin;

select plan(22);

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

select has_column('public','hr_employees','id','HR list query id column exists');
select has_column('public','hr_employees','employee_number','HR list query employee number column exists');
select has_column('public','hr_employees','first_name','HR list query first name column exists');
select has_column('public','hr_employees','last_name','HR list query last name column exists');
select has_column('public','hr_employees','email','HR list query email column exists');
select has_column('public','hr_employees','phone','HR list query phone column exists');
select has_column('public','hr_employees','department','HR list query department column exists');
select has_column('public','hr_employees','job_title','HR list query job title column exists');
select has_column('public','hr_employees','employment_type','HR list query employment type column exists');
select has_column('public','hr_employees','employment_status','HR list query employment status column exists');
select has_column('public','hr_employees','base_salary','HR list query base salary column exists');
select has_column('public','hr_employees','pay_frequency','HR list query pay frequency column exists');
select has_column('public','hr_employees','start_date','HR list query start date column exists');

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
