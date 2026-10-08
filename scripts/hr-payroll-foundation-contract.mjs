import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/20261008120000_add_hr_payroll_foundation.sql', 'utf8');
const hr = fs.readFileSync('src/pages/HumanResources.tsx', 'utf8');
const payroll = fs.readFileSync('src/pages/Payroll.tsx', 'utf8');
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
  if (!migration.includes(needle)) throw new Error('Missing HR/payroll security control: ' + needle);
}

for (const needle of ["'/hr':'hr'", "'/payroll':'payroll'", "'hr'", "'payroll'"]) {
  if (!permissions.includes(needle)) throw new Error('Missing permission: ' + needle);
}

for (const needle of [
  "const HumanResources = lazy(() => import('./pages/HumanResources'))",
  "const Payroll = lazy(() => import('./pages/Payroll'))",
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

console.log('HR/payroll foundation contract passed.');
