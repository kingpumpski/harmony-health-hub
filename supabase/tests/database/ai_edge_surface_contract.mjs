// Static regression contract for the AI Edge Function security boundary.
import fs from 'node:fs';
const p=fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts','utf8');
const checks=[
  ['no service-role key', !p.includes('SUPABASE_SERVICE_ROLE_KEY')],
  ['scoped case-memory RPC', p.includes('get_ai_case_memory_for_diagnosis')],
  ['scoped report RPC', p.includes('get_ai_report_requests')],
  ['guarded protocol draft RPC', p.includes('create_ai_protocol_draft')],
  ['profile lookup error checked', p.includes('callerProfileError')],
  ['portal read errors checked', p.includes('portalErrors')],
  ['dashboard read errors checked', p.includes('dashboardErrors')],
  ['scoped clinical context RPC', p.includes("rpc('get_ai_clinical_context'")],
  ['no broad clinical context selects', !p.includes("from('lab_orders').select('*')") && !p.includes("from('prescriptions').select('*')") && !p.includes("from('imaging_orders').select('*')")],
];
for (const [name,ok] of checks) { if(!ok) throw new Error('AI edge contract failed: '+name); }
console.log('AI edge surface contract passed');
