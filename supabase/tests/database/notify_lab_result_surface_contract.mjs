import fs from 'node:fs';

const fn = fs.readFileSync('supabase/functions/notify-lab-result/index.ts', 'utf8');
const page = fs.readFileSync('src/pages/Laboratory.tsx', 'utf8');

const checks = [
  ['authentication required', fn.includes("authClient.auth.getUser(token)")],
  ['canonical role lookup', fn.includes("from('user_roles').select('role')")],
  ['allowed role boundary', fn.includes('ALLOWED_ROLES')],
  ['server-side lab order lookup', fn.includes("from('lab_orders')") && fn.includes("select('id,patient_id,test_name,status')")],
  ['approved result gate', fn.includes("order.status !== 'approved'")],
  ['server-side patient lookup', fn.includes("from('patients')") && fn.includes("select('id,email,first_name,last_name')")],
  ['client sends only lab order id', page.includes("notify-lab-result', { body: { labOrderId: orderId } })"],
  ['client no longer supplies patient email', !page.includes('patientEmail: patient.email'),
  ['client no longer supplies patient name', !page.includes('patientName:'),
];

for (const [name, ok] of checks) {
  if (!ok) throw new Error('Lab result notification contract failed: ' + name);
}

console.log('Lab result notification surface contract passed');
