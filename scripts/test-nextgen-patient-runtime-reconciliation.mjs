import fs from 'node:fs';
import path from 'node:path';

const root=process.cwd();
const migration=fs.readFileSync(path.join(root,'supabase/migrations/20261008162000_reconcile_current_main_patient_runtime.sql'),'utf8');
const hub=fs.readFileSync(path.join(root,'src/pages/patients/PatientHub.tsx'),'utf8');
const portal=fs.readFileSync(path.join(root,'src/pages/PatientPortal.tsx'),'utf8');

const requiredMigration=[
  'CREATE OR REPLACE FUNCTION public.get_patient_portal_identity()',
  'CREATE OR REPLACE FUNCTION public.get_patient_appointments(',
  'CREATE OR REPLACE FUNCTION public.get_patient_hub_clinical_snapshot(',
  "public.has_role(uid,'patient')",
  "public.has_role(uid,'system_superuser')",
  'patient.user_id=uid',
  'REVOKE ALL ON FUNCTION public.get_patient_appointments(uuid,integer) FROM PUBLIC,anon',
];
for(const token of requiredMigration){
  if(!migration.includes(token)) throw new Error('Patient runtime reconciliation missing: '+token);
}
for(const token of [
  "db.rpc('get_patient_appointments', { _patient_id: patientId, _limit: 100 }, { get: true })",
  "db.rpc('get_patient_hub_clinical_snapshot', { _patient_id: patientId }, { get: true })",
  "db.rpc('get_patient_admission_history', { _patient_id: patientId }, { get: true })",
  "db.rpc('get_patient_invoices', { _patient_id: patientId, _limit: 100 })",
]){
  if(!hub.includes(token)) throw new Error('Patient Hub must use governed read RPC: '+token);
}
for(const token of [
  "supabase.rpc('get_patient_appointments', { _patient_id: portalPatient.id, _limit: 25 }, { get: true })",
  "supabase.rpc('get_patient_hub_clinical_snapshot', { _patient_id: portalPatient.id }, { get: true })",
]){
  if(!portal.includes(token)) throw new Error('Patient Portal read boundary missing: '+token);
}
if(hub.includes(".from('appointments').select('*').eq('patient_id', patientId)") ||
   hub.includes(".from('vital_signs').select('*').eq('patient_id', patientId)")){
  throw new Error('Patient Hub still contains direct broad clinical-history reads');
}
console.log('Patient runtime reconciliation contract: PASS');
