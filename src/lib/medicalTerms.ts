// Common medical autocomplete terms
export const MEDICAL_TERMS = [
  'Hypertension','Diabetes mellitus','Malaria','Pneumonia','Asthma','Bronchitis','Tuberculosis',
  'Anaemia','Sickle cell crisis','Hepatitis','Gastroenteritis','UTI','Appendicitis','Cholera',
  'Typhoid','Meningitis','Migraine','Epilepsy','Stroke','Myocardial infarction','Angina',
  'Heart failure','COPD','Sinusitis','Tonsillitis','Otitis media','Conjunctivitis','Glaucoma',
  'Cataract','Eczema','Psoriasis','Cellulitis','Sepsis','HIV/AIDS','COVID-19','Dengue fever',
  'Yellow fever','Pyelonephritis','Cystitis','Cervicitis','Endometritis','Pre-eclampsia',
  'Eclampsia','Postpartum haemorrhage','Antepartum haemorrhage','Anaphylaxis','Hyperthyroidism',
  'Hypothyroidism','Pancreatitis','Cholecystitis','Hernia','Osteoarthritis','Rheumatoid arthritis',
  'Gout','Paracetamol','Amoxicillin','Amlodipine','Metformin','Insulin','Lisinopril',
  'Hydrochlorothiazide','Atorvastatin','Omeprazole','Salbutamol','Prednisolone','Ciprofloxacin',
  'Artemether-Lumefantrine','Doxycycline','Ibuprofen','Diclofenac','Tramadol','Morphine','Codeine',
];

export interface DiagnosisSuggestion {
  label: string;
  code: string;
  source: 'ICD-10' | 'STG-Ghana';
}

export function searchDiagnosisTerms(q: string, limit = 8): DiagnosisSuggestion[] {
  if (!q || q.trim().length < 2) return [];
  const lower = q.trim().toLowerCase();
  return MEDICAL_TERMS
    .filter((term) => term.toLowerCase().includes(lower))
    .slice(0, limit)
    .map((label) => ({ label, code: '', source: 'ICD-10' as const }));
}

export function searchTerms(q: string, limit = 8) {
  if (!q || q.length < 2) return [];
  const lower = q.toLowerCase();
  return MEDICAL_TERMS.filter(t => t.toLowerCase().includes(lower)).slice(0, limit);
}
