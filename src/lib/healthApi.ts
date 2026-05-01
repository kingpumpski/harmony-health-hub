import { Patient, VitalSigns } from '@/types';

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export function registerPatient(payload: Partial<Patient>) {
  return wait(200).then(() => ({ success: true, patientId: payload.patientId ?? 'P-0000', payload }));
}

export function registerPatientFromDocument(document: File) {
  return wait(250).then(() => ({
    success: true,
    extracted: {
      fullName: 'Extracted Name',
      ghanaCardNumber: 'GHA-2026-0001',
      insuranceProvider: 'National Health Insurance',
      phone: '+233 24 000 0000',
    },
  }));
}

export function analyzeDocument(document: File) {
  return wait(300).then(() => ({
    success: true,
    findings: [
      'OCR extracted patient demographics and insurance details.',
      'No obvious drug interactions detected for current medication.',
      'Recommend physician review for referral and treatment planning.',
    ],
  }));
}

export function verifyGhanaCard(cardNumber: string) {
  return wait(250).then(() => ({ success: cardNumber.startsWith('GHA'), verified: true, authority: 'National Identification Authority Ghana' }));
}

export function getPatientById(id: string) {
  return wait(200).then(() => ({ id, patientId: id, fullName: 'Demo Patient' }));
}

export function updatePatient(id: string, data: Partial<Patient>) {
  return wait(200).then(() => ({ success: true, id, data }));
}

const mockPatients = [
  { id: 'P-001', patientId: 'MED-20260501-1234', firstName: 'Agyapong', lastName: 'Kofi', fullName: 'Agyapong Kofi', phone: '+233 24 123 4567', ghanaCardNumber: 'GHA-2026-0001', status: 'active' },
  { id: 'P-002', patientId: 'MED-20260502-2345', firstName: 'Ama', lastName: 'Boateng', fullName: 'Ama Boateng', phone: '+233 24 765 4321', ghanaCardNumber: 'GHA-2026-0002', status: 'active' },
  { id: 'P-003', patientId: 'MED-20260503-3456', firstName: 'Kwesi', lastName: 'Appiah', fullName: 'Kwesi Appiah', phone: '+233 24 987 6543', ghanaCardNumber: 'GHA-2026-0003', status: 'discharged' },
];

export function searchPatients(query: string) {
  const lowerQuery = query.toLowerCase();
  return wait(150).then(() =>
    mockPatients.filter((patient) =>
      patient.patientId.toLowerCase().includes(lowerQuery) ||
      (patient.fullName && patient.fullName.toLowerCase().includes(lowerQuery)) ||
      patient.phone?.toLowerCase().includes(lowerQuery) ||
      patient.ghanaCardNumber?.toLowerCase().includes(lowerQuery)
    )
  );
}

export function recordTriageVitals(vitals: VitalSigns) {
  return wait(180).then(() => ({ success: true, vitals }));
}

export function evaluateTriagePriority(vitals: VitalSigns) {
  if (vitals.temperature >= 39 || vitals.oxygenSaturation <= 92 || vitals.heartRate >= 120 || vitals.bloodPressure.systolic >= 180) {
    return 'Critical';
  }
  if (vitals.temperature >= 38 || vitals.oxygenSaturation <= 94 || vitals.heartRate >= 100 || vitals.bloodPressure.systolic >= 160) {
    return 'Urgent';
  }
  return 'Moderate';
}

export function getCriticalPatients() {
  return wait(200).then(() => [{ id: 'P-100', name: 'Critical Patient', priority: 'Critical' }]);
}

export function getWaitingList() {
  return wait(200).then(() => [{ id: 'P-101', name: 'Waiting Patient', priority: 'Moderate' }]);
}

export function createConsultationEncounter(payload: any) {
  return wait(200).then(() => ({ success: true, encounter: payload }));
}

export function addDiagnosisToConsultation(diagnosis: string) {
  return wait(150).then(() => ({ success: true, diagnosis }));
}

export function setPrincipalDiagnosis(diagnosis: string) {
  return wait(150).then(() => ({ success: true, principalDiagnosis: diagnosis }));
}

export function completeConsultation(data: { encounterId: string; principalDiagnosis: string }) {
  return wait(180).then(() => ({ success: true, data }));
}

export function orderLabTest(payload: any) {
  return wait(180).then(() => ({ success: true, order: payload }));
}

export function collectLabSample(orderId: string) {
  return wait(180).then(() => ({ success: true, orderId }));
}

export function uploadLabResult(orderId: string, result: any) {
  return wait(180).then(() => ({ success: true, orderId, result }));
}

export function validateLabResult(orderId: string) {
  return wait(150).then(() => ({ success: true, orderId }));
}

export function getLabResults(patientId: string) {
  return wait(180).then(() => [{ patientId, results: [] }]);
}

export function configureSoundAlert(config: any) {
  return wait(120).then(() => ({ success: true, config }));
}

export function listSoundAlerts() {
  return wait(120).then(() => []);
}

export function triggerSoundAlert(alertId: string) {
  return wait(120).then(() => ({ success: true, alertId }));
}

export function generatePublicHealthReport(templateId: string) {
  return wait(250).then(() => ({ success: true, report: templateId }));
}

export function generateRoster(department: string, weekStart: string) {
  return wait(200).then(() => ({ success: true, department, weekStart }));
}

export function analyzeWithAI(module: string, payload: any) {
  return wait(200).then(() => ({ success: true, module, payload }));
}
