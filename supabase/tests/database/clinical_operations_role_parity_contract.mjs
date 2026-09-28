import fs from 'node:fs';

const app = fs.readFileSync('src/App.tsx', 'utf8');
const page = fs.readFileSync('src/pages/ClinicalOperations.tsx', 'utf8');
const migration = fs.readFileSync('supabase/migrations/20260921121000_post_merge_runtime_role_lookup_fix.sql', 'utf8');

const expectedRoles = ['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse'];

if (!app.includes("const clinicalOperationsRoles = ['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse'] as const;")) throw new Error('Clinical Operations route role set is missing or broadened');
if (!app.includes('<Route path="/clinical-operations" element={<RoleGuard allowedRoles={clinicalOperationsRoles}><ClinicalOperations /></RoleGuard>} />')) throw new Error('Clinical Operations route is not guarded by the dedicated operational role set');
if (page.includes("accountant: ['insurance']")) throw new Error('Accountant must use the dedicated insurance claims surface, not Clinical Operations');
for (const role of expectedRoles) if (!page.includes(role + ': [')) throw new Error('Clinical Operations page missing role: ' + role);
if (!migration.includes("ELSIF _module='insurance'")) throw new Error('Insurance workspace branch missing');
if (!migration.includes("public.has_role(auth.uid(),'accountant')")) throw new Error('Insurance workspace accountant authorization missing');
if (!migration.includes("ELSIF _module='ward'")) throw new Error('Ward workspace branch missing');
if (!migration.includes("ELSIF _module='nursing_care'")) throw new Error('Nursing workspace branch missing');
if (!migration.includes("ELSIF _module='emergency'")) throw new Error('Emergency workspace branch missing');
if (!migration.includes("ELSIF _module='theatre'")) throw new Error('Theatre workspace branch missing');
if (!migration.includes("ELSIF _module='transfusion'")) throw new Error('Transfusion workspace branch missing');
if (!migration.includes('REVOKE ALL ON FUNCTION public.get_operational_workspace(text,integer) FROM PUBLIC, anon;')) throw new Error('Operational workspace public/anon execute revoke missing');
console.log('Clinical Operations role parity contract passed');