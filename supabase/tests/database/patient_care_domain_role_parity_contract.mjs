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
if (!snapshot.includes("is_lab := public.has_role(uid,'lab_technician')")) {
  throw new Error('laboratory role boundary is missing from the patient clinical snapshot');
}
if (!snapshot.includes("is_pharmacy := public.has_role(uid,'pharmacist')")) {
  throw new Error('pharmacy role boundary is missing from the patient clinical snapshot');
}
if (snapshot.includes("public.has_role(uid,'accountant')") || snapshot.includes("public.has_role(uid,'front_desk')") || snapshot.includes("public.has_role(uid,'radiology_technician')") || snapshot.includes("public.has_role(uid,'radiologist')")) {
  throw new Error('patient clinical snapshot must not grant broad or radiology-only roles longitudinal clinical history access');
}
if (!snapshot.includes('revoke all on function public.get_patient_hub_clinical_snapshot(uuid) from public, anon;')) {
  throw new Error('patient clinical snapshot must remain non-public and non-anonymous');
}
if (!history.includes("public.has_role(auth.uid(),'radiology_technician')")) {
  throw new Error('radiology technician appointment read access is missing');
}
if (app.includes('PatientCareContinuity /></RoleGuard>}') && app.includes('allowedRoles={patientRecordsRoles}><PatientCareContinuity')) {
  throw new Error('continuity route regressed to the broad patient-record role set');
}

const patientSearch = fs.readFileSync('src/pages/patients/PatientSearch.tsx', 'utf8');
if (!patientSearch.includes("const canRegister = roleSet.has('admin') || roleSet.has('front_desk');")) {
  throw new Error('patient search registration action must follow the registration route role boundary');
}
if (!patientSearch.includes("const canChat = roleSet.has('admin') || roleSet.has('practitioner') || roleSet.has('nurse') || roleSet.has('specialist_nurse') || roleSet.has('midwife') || roleSet.has('patient');")) {
  throw new Error('patient search chat action must follow the patient-chat route role boundary');
}
if (!patientSearch.includes('{canRegister && <Link to="/registration"')) {
  throw new Error('patient search must not expose registration navigation to unauthorized roles');
}
if (!patientSearch.includes('{canChat && <Link')) {
  throw new Error('patient search must not expose patient chat navigation to unauthorized roles');
}

const patientHub = fs.readFileSync('src/pages/patients/PatientHub.tsx', 'utf8');
if (!patientHub.includes("const clinicalHistoryRoles = new Set(['admin', 'practitioner', 'nurse', 'midwife', 'specialist_nurse', 'lab_technician', 'pharmacist']);")) {
  throw new Error('patient hub clinical history role boundary must remain explicit');
}
if (!patientHub.includes("...(canClinicalHistory ? [['clinical', db.rpc('get_patient_hub_clinical_snapshot'")) {
  throw new Error('patient hub must not request clinical snapshot data for non-clinical-history roles');
}

console.log('Patient care domain role parity contract passed');
