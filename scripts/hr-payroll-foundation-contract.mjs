import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20261008120000_add_hr_payroll_foundation.sql', 'utf8');
const recordManagementMigration = fs.readFileSync('supabase/migrations/20261015080000_add_hr_payroll_record_management.sql', 'utf8');
const hr = fs.readFileSync('src/pages/HumanResources.tsx', 'utf8');
const payroll = fs.readFileSync('src/pages/Payroll.tsx', 'utf8');
const hrPayrollDatabaseContract = fs.readFileSync('supabase/tests/database/hr_payroll_record_management_contract.sql', 'utf8');
const insurance = fs.readFileSync('src/pages/admin/InsuranceCompanies.tsx', 'utf8');
const clinicalReferences = fs.readFileSync('src/pages/admin/ClinicalReferences.tsx', 'utf8');
const permissions = fs.readFileSync('src/lib/permissions.ts', 'utf8');
const app = fs.readFileSync('src/App.tsx', 'utf8');
const sidebar = fs.readFileSync('src/components/layout/Sidebar.tsx', 'utf8');

for (const needle of [
  'create table if not exists public.hr_employees',
  'create table if not exists public.payroll_periods',
  'create table if not exists public.payroll_items',
  'alter table public.hr_employees enable row level security',
  'alter table public.payroll_periods enable row level security',
  'alter table public.payroll_items enable row level security',
  'create or replace function public.generate_payroll_items(_payroll_period_id uuid)',
  'revoke all on function public.generate_payroll_items(uuid) from public, anon',
  'grant execute on function public.generate_payroll_items(uuid) to authenticated',
  'current_user_has_role',
]) {
  if (!migration.toLowerCase().includes(needle)) throw new Error('Missing HR/payroll security control: ' + needle);
}

const employeeFieldsMatch = hr.match(/const employeeFields = '([^']+)'/);
if (!employeeFieldsMatch) throw new Error('HR employee list must declare its selected database fields in one contract.');
const employeeFields = employeeFieldsMatch[1].split(',').map((field) => field.trim());
const canonicalEmployeeFields = [
  'id', 'employee_number', 'first_name', 'last_name', 'email', 'phone',
  'department', 'job_title', 'employment_type', 'employment_status',
  'base_salary', 'pay_frequency', 'start_date', 'archived_at',
];
for (const column of canonicalEmployeeFields) {
  if (!employeeFields.includes(column)) {
    throw new Error('HR employee list is missing required field: ' + column);
  }
  if (!hrPayrollDatabaseContract.includes(`'hr_employees','${column}'`)) {
    throw new Error('HR database contract does not verify selected column: ' + column);
  }
  if (!(migration + '\n' + recordManagementMigration).toLowerCase().includes(column)) {
    throw new Error('HR schema migrations do not declare selected column: ' + column);
  }
}
if (!hr.includes(".order('last_name')") || !hr.includes(".order('first_name')")) {
  throw new Error('HR employee list ordering must use columns verified by the schema contract.');
}
if (!hr.includes("archived_by: archiving ? user.id : null")) {
  throw new Error('HR archive writes must preserve actor attribution through archived_by.');
}

for (const needle of ["'/hr':'hr'", "'/payroll':'payroll'", "'hr'", "'payroll'"]) {
  if (!permissions.includes(needle)) throw new Error('Missing permission: ' + needle);
}

for (const needle of [
  "const HumanResources = lazyWithChunkRecovery(() => import('./pages/HumanResources'))",
  "const Payroll = lazyWithChunkRecovery(() => import('./pages/Payroll'))",
  'path="/hr"',
  'path="/payroll"',
]) {
  if (!app.includes(needle)) throw new Error('Missing route: ' + needle);
}

for (const needle of ['Human Resources', 'Payroll']) {
  if (!sidebar.includes(needle)) throw new Error('Missing navigation item: ' + needle);
}

if (!hr.includes("from('hr_employees')")) throw new Error('HR workspace is not connected to hr_employees.');
if (!payroll.includes("from('payroll_periods')") || !payroll.includes('generate_payroll_items')) {
  throw new Error('Payroll workspace is not connected to payroll runtime.');
}

for (const needle of [
  'add column if not exists archived_at timestamptz',
  'add column if not exists archived_by uuid',
  'create trigger hr_employees_record_management_guard',
  'create trigger payroll_periods_record_management_guard',
  'create trigger payroll_items_record_management_guard',
  'hr_employees_deny_hard_delete',
  'payroll_periods_deny_hard_delete',
  'payroll_items_deny_hard_delete',
  'and e.archived_at is null',
  "if v_status <> 'draft' then",
]) {
  if (!recordManagementMigration.toLowerCase().includes(needle)) {
    throw new Error('Missing HR/payroll record-management control: ' + needle);
  }
}

for (const needle of ['openEdit', 'archived_at', 'setArchived', 'showArchived', 'search employees']) {
  if (!hr.toLowerCase().includes(needle.toLowerCase())) {
    throw new Error('Missing workforce record-management UI: ' + needle);
  }
}

for (const needle of ['openEditPeriod', 'savePeriod', 'openEditItem', 'saveItem', 'voidItem', 'cancelPeriod']) {
  if (!payroll.includes(needle)) throw new Error('Missing payroll record-management UI: ' + needle);
}

if (!hrPayrollDatabaseContract.includes('payroll_items_deny_hard_delete')) {
  throw new Error('Missing database verification for payroll record-management policies.');
}

for (const needle of ['update_insurance_company', 'create_insurance_company']) {
  if (!insurance.includes(needle)) throw new Error('Insurance master data is missing CRUD support: ' + needle);
}
if (!clinicalReferences.includes(".update(payload)") || !clinicalReferences.includes(".insert(payload)")) {
  throw new Error('Clinical reference master data is missing create/update workflows.');
}

console.log('HR/payroll foundation and employee query schema contract passed.');
