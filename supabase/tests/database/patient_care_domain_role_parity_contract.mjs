import fs from 'node:fs';

const app = fs.readFileSync('src/App.tsx', 'utf8');
const directory = fs.readFileSync('supabase/migrations/20260920093000_staff_directory_notification_least_privilege.sql', 'utf8');
const snapshot = fs.readFileSync('supabase/migrations/20260921084058_add_patient_hub_clinical_snapshot.sql', 'utf8');
const history = fs.readFileSync('supabase/migrations/20260921120000_post_merge_runtime_patient_history_rpcs.sql', 'utf8');

if (!app.includes("const patientRecordsRoles = ['admin', 'practitioner', 'nurse', 'specialist_nurse', 'radiologist', 'radiology_technician', 'front_desk'] as const;")) {
  throw new Error('patient record route role set drifted');
}
if (!app.includes("const patientContinuityRoles = ['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'pharmacist', 'lab_technician'] as const;")) {
  throw new Error('patient continuity route must match the sensitive continuity backend boundary');
}
if (!app.includes('<Route path="/patients/:patientId/continuity" element={<RoleGuard allowedRoles={patientContinuityRoles}><PatientCareContinuity /></RoleGuard>} />')) {
  throw new Error('patient continuity route is not protected by its dedicated role boundary');
}
if (!directory.includes("OR has_role(auth.uid(), 'radiology_technician'::app_role)")) {
  throw new Error('radiology technician patient-directory access is missing');
}
if (!snapshot.includes("public.has_role(uid,'radiology_technician')")) {
  throw new Error('radiology technician patient clinical read access is missing');
}
if (!history.includes("public.has_role(auth.uid(),'radiology_technician')")) {
  throw new Error('radiology technician appointment read access is missing');
}
if (app.includes('PatientCareContinuity /></RoleGuard>}') && app.includes('allowedRoles={patientRecordsRoles}><PatientCareContinuity')) {
  throw new Error('continuity route regressed to the broad patient-record role set');
}

console.log('Patient care domain role parity contract passed');
