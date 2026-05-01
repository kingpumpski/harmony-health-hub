export interface ClinicalReference {
  code: string;
  description: string;
  category: string;
  guideline: string;
}

export interface TreatmentGuideline {
  condition: string;
  summary: string;
  recommendedAction: string;
}

export const icdReferences: ClinicalReference[] = [
  {
    code: 'A09',
    description: 'Diarrhoea and gastroenteritis of presumed infectious origin',
    category: 'Infectious diseases',
    guideline: 'Provide hydration therapy and refer for stool analysis if symptoms persist beyond 48 hours.',
  },
  {
    code: 'E10',
    description: 'Type 1 diabetes mellitus',
    category: 'Endocrine, nutritional and metabolic diseases',
    guideline: 'Begin insulin therapy and schedule regular blood glucose monitoring.',
  },
  {
    code: 'I10',
    description: 'Essential (primary) hypertension',
    category: 'Circulatory system',
    guideline: 'Lifestyle modification and antihypertensive agents according to Ghana STG.',
  },
  {
    code: 'J06',
    description: 'Acute upper respiratory infections of multiple and unspecified sites',
    category: 'Respiratory diseases',
    guideline: 'Treat supportively and escalate if high-risk signs appear.',
  },
  {
    code: 'N39',
    description: 'Other disorders of urinary system',
    category: 'Genitourinary system',
    guideline: 'Assess for urinary tract infection and manage with appropriate antibiotics.',
  },
];

export const treatmentGuidelines: TreatmentGuideline[] = [
  {
    condition: 'Malaria',
    summary: 'Use rapid diagnostic test followed by ACT when positive. Monitor for severe disease and refer if necessary.',
    recommendedAction: 'Administer artesunate-based combination therapy and provide supportive fluids.',
  },
  {
    condition: 'Hypertension',
    summary: 'Diagnose with repeated BP measurements. Start lifestyle and medication based on risk stratification.',
    recommendedAction: 'Begin with ACE inhibitors or calcium channel blockers and follow Ghana MoH protocols.',
  },
  {
    condition: 'Type 2 diabetes mellitus',
    summary: 'Confirm with fasting glucose or HbA1c. Start lifestyle measures and metformin if no contraindications.',
    recommendedAction: 'Provide structured education, glucose monitoring, and early drug therapy when needed.',
  },
  {
    condition: 'Pneumonia',
    summary: 'Classify severity, administer antibiotics, and offer oxygen therapy for moderate to severe disease.',
    recommendedAction: 'Give amoxicillin or appropriate alternative and admit if respiratory distress present.',
  },
];

const templateHeaders = {
  patients: ['patientId', 'firstName', 'lastName', 'dateOfBirth', 'gender', 'email', 'phone', 'address', 'ghanaCardNumber', 'insuranceProvider'],
  staff: ['userId', 'fullName', 'email', 'role', 'department', 'specialization', 'phone', 'startDate'],
  tariff: ['tariffCode', 'serviceName', 'category', 'priceGHS', 'effectiveDate'],
  insurance: ['providerName', 'planName', 'coverageType', 'policyNumberFormat', 'contactInfo'],
  medication: ['drugName', 'dosageForm', 'strength', 'unitPrice', 'stockLevel', 'therapeuticClass'],
  guidelines: ['code', 'condition', 'recommendedAction', 'notes'],
};

export function downloadCsvTemplate(type: keyof typeof templateHeaders) {
  const headers = templateHeaders[type];
  const sampleRow = headers.map((header) => `${header}_example`);
  const csvContent = [headers.join(','), sampleRow.join(',')].join('\n');
  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.setAttribute('download', `${type}-template.csv`);
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}
