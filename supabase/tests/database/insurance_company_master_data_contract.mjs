import fs from 'node:fs';
const sql=fs.readFileSync('supabase/migrations/20260929100000_insurance_company_master_data.sql','utf8');
const required=[
  'CREATE TABLE IF NOT EXISTS public.insurance_companies',
  'ALTER TABLE public.insurance_companies ENABLE ROW LEVEL SECURITY',
  'public.has_role(auth.uid(),\'admin\') OR public.has_role(auth.uid(),\'it_admin\')',
  'CREATE OR REPLACE FUNCTION public.create_insurance_company',
  'CREATE OR REPLACE FUNCTION public.update_insurance_company',
  'CREATE OR REPLACE FUNCTION public.list_insurance_companies',
  'insurance_company_id uuid REFERENCES public.insurance_companies(id)',
  "('insurance_companies','Manage the insurance company master directory',true)"
];
const missing=required.filter(fragment=>!sql.includes(fragment));
if(missing.length){console.error('Insurance company master-data contract failed:',missing.join(', '));process.exitCode=1;}
else console.log('Insurance company master-data contract: all invariants present');