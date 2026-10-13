import type { UserRole } from '@/types';

export type SpecialtyId =
  | 'general_practitioner'
  | 'dentist'
  | 'ophthalmologist'
  | 'physiotherapist'
  | 'orthopaedic'
  | 'dietician';

export type SpecialtyModule =
  | 'dashboard'
  | 'patients'
  | 'appointments'
  | 'triage'
  | 'encounters'
  | 'clinical_operations'
  | 'inpatient'
  | 'emergency'
  | 'theatre'
  | 'transfusion'
  | 'department_queue'
  | 'laboratory'
  | 'laboratory_results'
  | 'radiology_results'
  | 'radiology'
  | 'pharmacy'
  | 'billing'
  | 'finance'
  | 'dental_chart'
  | 'procedures'
  | 'ophthalmology'
  | 'physio_assessment'
  | 'dietary_assessment'
  | 'dietary_plans'
  | 'meal_orders'
  | 'notifications'
  | 'referrals'
  | 'reports'
  | 'anesthesia'
  | 'telemedicine'
  | 'fertility'
  | 'ai_clinical';

export const SPECIALTY_MODULES: Record<SpecialtyId, readonly SpecialtyModule[]> = {
  general_practitioner: [
    'dashboard', 'patients', 'appointments', 'triage', 'encounters', 'clinical_operations', 'inpatient',
    'emergency', 'theatre', 'transfusion', 'department_queue', 'laboratory_results', 'radiology_results',
    'laboratory', 'radiology', 'pharmacy', 'billing', 'finance', 'procedures', 'anesthesia',
    'telemedicine', 'fertility', 'ai_clinical', 'reports', 'referrals',
  ],
  dentist: [
    'dashboard', 'patients', 'appointments', 'encounters', 'clinical_operations', 'dental_chart',
    'procedures', 'laboratory', 'laboratory_results', 'radiology_results', 'radiology', 'billing', 'finance',
    'notifications',
  ],
  ophthalmologist: [
    'dashboard', 'patients', 'appointments', 'encounters', 'clinical_operations', 'ophthalmology',
    'radiology', 'radiology_results', 'laboratory', 'laboratory_results', 'procedures', 'billing', 'finance',
    'notifications',
  ],
  physiotherapist: [
    'dashboard', 'patients', 'appointments', 'encounters', 'clinical_operations', 'physio_assessment',
    'procedures', 'billing', 'finance', 'notifications',
  ],
  orthopaedic: [
    'dashboard', 'patients', 'appointments', 'encounters', 'clinical_operations', 'radiology',
    'radiology_results', 'theatre', 'procedures', 'billing', 'finance', 'notifications',
  ],
  dietician: [
    'dashboard', 'patients', 'appointments', 'encounters', 'clinical_operations', 'dietary_assessment',
    'dietary_plans', 'meal_orders', 'billing', 'finance', 'notifications',
  ],
};

const roleSpecialty: Partial<Record<UserRole, SpecialtyId>> = {
  dentist: 'dentist',
  ophthalmologist: 'ophthalmologist',
  physiotherapist: 'physiotherapist',
  dietician: 'dietician',
};

const aliases: Record<string, SpecialtyId> = {
  gp: 'general_practitioner',
  general: 'general_practitioner',
  'general practitioner': 'general_practitioner',
  'general practice': 'general_practitioner',
  'family medicine': 'general_practitioner',
  dentist: 'dentist',
  dental: 'dentist',
  dentistry: 'dentist',
  ophthalmologist: 'ophthalmologist',
  ophthalmology: 'ophthalmologist',
  optometrist: 'ophthalmologist',
  physiotherapist: 'physiotherapist',
  physiotherapy: 'physiotherapist',
  physio: 'physiotherapist',
  orthopaedic: 'orthopaedic',
  orthopedics: 'orthopaedic',
  orthopaedics: 'orthopaedic',
  'orthopedic surgeon': 'orthopaedic',
  'orthopaedic surgeon': 'orthopaedic',
  dietician: 'dietician',
  dietitian: 'dietician',
  dietetics: 'dietician',
  nutritionist: 'dietician',
};

export function normalizeSpecialty(value?: string | null): SpecialtyId | null {
  const normalized = value?.trim().toLowerCase().replace(/[_-]+/g, ' ').replace(/\s+/g, ' ');
  return normalized ? aliases[normalized] ?? null : null;
}

export function resolveUserSpecialty(role: UserRole, specialization?: string | null): SpecialtyId | null {
  const assignedRoleSpecialty = roleSpecialty[role];
  if (assignedRoleSpecialty) return assignedRoleSpecialty;
  const profileSpecialty = normalizeSpecialty(specialization);
  if (profileSpecialty) return profileSpecialty;
  return role === 'practitioner' ? 'general_practitioner' : null;
}

export function moduleForPath(pathname: string): SpecialtyModule | null {
  const routes: Array<[string, SpecialtyModule]> = [
    ['/dashboard', 'dashboard'],
    ['/patients', 'patients'],
    ['/appointments', 'appointments'],
    ['/review-appointments', 'appointments'],
    ['/vitals', 'triage'],
    ['/monitoring', 'triage'],
    ['/encounters', 'encounters'],
    ['/consultation', 'encounters'],
    ['/clinical-operations', 'clinical_operations'],
    ['/ward-bed-board', 'inpatient'],
    ['/inpatient', 'inpatient'],
    ['/inpatients', 'inpatient'],
    ['/admissions', 'inpatient'],
    ['/care-transitions', 'inpatient'],
    ['/nursing-handover', 'triage'],
    ['/emergency-board', 'emergency'],
    ['/theatre-board', 'theatre'],
    ['/transfusion-board', 'transfusion'],
    ['/department-queue', 'department_queue'],
    ['/lab-requests', 'laboratory'],
    ['/laboratory', 'laboratory'],
    ['/outside-lab', 'laboratory'],
    ['/results-entry', 'laboratory_results'],
    ['/lab-results', 'laboratory_results'],
    ['/clinical-results', 'radiology_results'],
    ['/imaging', 'radiology'],
    ['/radiology', 'radiology'],
    ['/medications', 'pharmacy'],
    ['/pharmacy', 'pharmacy'],
    ['/dispensing', 'pharmacy'],
    ['/inventory', 'pharmacy'],
    ['/stock-alerts', 'pharmacy'],
    ['/invoices', 'billing'],
    ['/insurance-claims', 'billing'],
    ['/accounts-approvals', 'billing'],
    ['/billing', 'billing'],
    ['/finance', 'finance'],
    ['/insurance', 'finance'],
    ['/financial-reports', 'finance'],
    ['/dental', 'dental_chart'],
    ['/treatment-templates', 'procedures'],
    ['/procedures', 'procedures'],
    ['/ophthalmology', 'ophthalmology'],
    ['/physio', 'physio_assessment'],
    ['/dietary-plans', 'dietary_plans'],
    ['/specialist-referrals', 'referrals'],
    ['/records', 'patients'],
    ['/orders', 'meal_orders'],
    ['/menu', 'meal_orders'],
    ['/notifications', 'notifications'],
    ['/notification-preferences', 'notifications'],
    ['/sound-alerts', 'notifications'],
    ['/reports', 'reports'],
    ['/reports/submissions', 'reports'],
    ['/ai-report', 'reports'],
    ['/public-health', 'reports'],
    ['/anesthesia', 'anesthesia'],
    ['/telemedicine', 'telemedicine'],
    ['/fertility', 'fertility'],
    ['/ai-clinical', 'ai_clinical'],
  ];
  return routes.find(([prefix]) => pathname === prefix || pathname.startsWith(`${prefix}/`))?.[1] ?? null;
}

export function isSpecialtyModuleAllowed(
  specialty: SpecialtyId | null,
  module: SpecialtyModule,
): boolean {
  return specialty === null || SPECIALTY_MODULES[specialty].includes(module);
}
