import fs from 'node:fs';
const p=fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts','utf8');
const forbidden=["from('appointments').select('*')","from('vital_signs').select('*')","from('triage_assessments').select('*')","from('encounters').select('*')","from('lab_orders').select('*')","from('prescriptions').select('*')","from('imaging_orders').select('*')","from('procedure_notes').select('*')","from('anesthetic_assessments').select('*')","from('lab_results').select('*')"];
for (const x of forbidden) if (p.includes(x)) throw new Error(`direct broad clinical read remains: ${x}`);
if (!p.includes("rpc('get_ai_clinical_context'")) throw new Error('scoped clinical context RPC missing');
console.log('AI clinical context surface contract passed');
