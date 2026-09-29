import fs from 'node:fs';

const sql = fs.readFileSync(
  'supabase/migrations/20260929150000_patient_canonical_insurer_linkage.sql',
  'utf8',
);

const required = [
  'CREATE OR REPLACE FUNCTION public.set_patient_insurance_company',
  "public.has_role(uid,'admin'::public.app_role)",
  "public.has_role(uid,'it_admin'::public.app_role)",
  "public.has_role(uid,'front_desk'::public.app_role)",
  "public.has_role(uid,'accountant'::public.app_role)",
  'FROM public.patients',
  'FOR UPDATE',
  'FROM public.insurance_companies c',
  'c.active=true',
  'Active canonical insurance company not found',
  'insurance_company_id=_insurance_company_id',
  'patient_insurance_company_linked',
  'REVOKE ALL ON FUNCTION public.set_patient_insurance_company(uuid,uuid) FROM PUBLIC,anon',
  'GRANT EXECUTE ON FUNCTION public.set_patient_insurance_company(uuid,uuid) TO authenticated',
];

const missing = required.filter((item) => !sql.includes(item));
if (missing.length) {
  console.error('Missing patient canonical insurer linkage contract requirements:', missing);
  process.exitCode = 1;
} else {
  console.log('Patient canonical insurer linkage contract passed.');
}