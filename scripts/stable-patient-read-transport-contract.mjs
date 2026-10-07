import fs from 'node:fs';
import assert from 'node:assert/strict';

const checks = [
  ['src/pages/PatientPortal.tsx', [
    "supabase.rpc('get_patient_portal_identity', {}, { get: true })",
    "supabase.rpc('get_patient_appointments', { _patient_id: portalPatient.id, _limit: 25 }, { get: true })",
    "supabase.rpc('get_patient_portal_video_sessions', { _limit: 25 }, { get: true })",
    "supabase.rpc('get_patient_invoice_summary', { _limit: 25 }, { get: true })",
    "supabase.rpc('get_ai_report_requests', { _patient_id: portalPatient.id, _limit: 25 }, { get: true })",
    "supabase.rpc('get_patient_hub_clinical_snapshot', { _patient_id: portalPatient.id }, { get: true })",
  ]],
  ['src/pages/MedicalRecords.tsx', [
    "supabase.rpc('get_patient_portal_identity', {}, { get: true })",
    "supabase.rpc('get_patient_hub_clinical_snapshot', { _patient_id: p.id }, { get: true })",
  ]],
  ['src/pages/Appointments.tsx', [
    "supabase.rpc('get_patient_portal_identity', {}, { get: true })",
    "supabase.rpc('get_patient_appointments', { _patient_id: p.id, _limit: 100 }, { get: true })",
  ]],
  ['src/pages/Telemedicine.tsx', [
    "supabase.rpc('get_patient_portal_video_sessions', { _limit: 50 }, { get: true })",
    "supabase.rpc('get_patient_telemedicine_clinicians', { _scheduled_at: new Date(at).toISOString() }, { get: true })",
  ]],
  ['src/pages/Billing.tsx', [
    "supabase.rpc('get_patient_invoice_summary', { _limit: 100 }, { get: true })",
  ]],
  ['src/pages/OutsideLabUploads.tsx', [
    "supabase.rpc('get_patient_outside_lab_documents', { _limit: 50 }, { get: true })",
  ]],
  ['src/pages/patients/PatientCareContinuity.tsx', [
    "supabase.rpc('get_patient_care_continuity', { _patient_id: patientId }, { get: true })",
  ]],
  ['src/pages/Encounters.tsx', [
    "supabase.rpc('get_patient_bmi_context', { _patient_id: patientId }, { get: true })",
  ]],
  ['supabase/functions/ai-clinical-assist/index.ts', [
    "supabase.rpc('get_patient_portal_identity', {}, { get: true })",
    "supabase.rpc('get_patient_appointments', { _patient_id: patient.id, _limit: 25 }, { get: true })",
    "supabase.rpc('get_patient_portal_video_sessions', { _limit: 25 }, { get: true })",
    "supabase.rpc('get_patient_invoice_summary', { _limit: 25 }, { get: true })",
    "supabase.rpc('get_ai_report_requests', { _patient_id: patient.id, _limit: 25 }, { get: true })",
    "supabase.rpc('get_patient_hub_clinical_snapshot', { _patient_id: body.patientId }, { get: true })",
  ]],
];

checks.push(['supabase/functions/ai-clinical-assist/index.ts', ["await Promise.allSettled([", "const isClinical = hasAnyRole(aiClinicalRoles);", "if (!isClinical && !hasAnyRole(['patient'])) throw new Error('Not authorised to generate this report');"]]);

for (const [file, needles] of checks) {
  const source = fs.readFileSync(file, 'utf8');
  for (const needle of needles) assert.ok(source.includes(needle), file + ': stable patient read must use explicit GET transport: ' + needle);
}

console.log('[stable-patient-read] All stable patient/portal RPC call sites use explicit GET transport.');


const aiClinicalAssist = fs.readFileSync('supabase/functions/ai-clinical-assist/index.ts', 'utf8');
assert.ok(aiClinicalAssist.includes("supabase.rpc('get_current_user_roles')"), 'AI clinical assist must resolve caller roles through the canonical security-definer role helper');
assert.ok(!aiClinicalAssist.includes("supabase.from('user_roles').select('role').eq('user_id', callerId)"), 'AI clinical assist must not depend directly on user_roles RLS');
console.log('[ai-clinical-role-resolution] canonical role helper contract passed.');
