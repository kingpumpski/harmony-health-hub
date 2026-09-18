import type { UserRole } from '@/types';

export type Permission =
  | 'dashboard' | 'patients' | 'finance' | 'administration' | 'registration' | 'appointments' | 'triage' | 'encounters'
  | 'clinical_operations' | 'inpatient' | 'ward' | 'handover' | 'emergency' | 'theatre' | 'transfusion'
  | 'claims' | 'reports' | 'report_submissions' | 'accounts_approvals' | 'tariff_adjustments'
  | 'department_queue' | 'laboratory' | 'laboratory_results' | 'radiology' | 'radiology_results' | 'pharmacy'
  | 'medication_administration' | 'billing' | 'maternity' | 'telemedicine' | 'fertility'
  | 'dental' | 'procedures' | 'anesthesia' | 'ophthalmology' | 'ai_clinical' | 'users'
  | 'system_library' | 'offline_sync' | 'data_import' | 'inpatients' | 'meal_orders'
  | 'notifications' | 'outside_lab' | 'financial_reports' | 'inventory' | 'stock_alerts'
  | 'patient_portal' | 'orders' | 'dietary_plans';

export const permissionByHref: Record<string, Permission> = {
  '/dashboard':'dashboard','/patients':'patients','/finance':'finance','/administration':'administration','/registration':'registration','/appointments':'appointments',
  '/vitals':'triage','/encounters':'encounters','/clinical-operations':'clinical_operations','/inpatient':'inpatient','/ward-bed-board':'inpatient',
  '/nursing-handover':'handover','/emergency-board':'emergency','/theatre-board':'theatre','/transfusion-board':'transfusion',
  '/insurance-claims':'claims','/reports':'reports','/reports/submissions':'report_submissions','/accounts-approvals':'accounts_approvals',
  '/billing/tariffs':'tariff_adjustments','/department-queue':'department_queue','/laboratory':'laboratory','/clinical-results':'laboratory_results',
  '/radiology':'radiology','/clinical-results':'radiology_results','/pharmacy':'pharmacy','/medications':'medication_administration',
  '/billing':'billing','/maternity':'maternity','/telemedicine':'telemedicine','/fertility':'fertility','/dental':'dental',
  '/procedures':'procedures','/anesthesia':'anesthesia','/ophthalmology':'ophthalmology','/ai-clinical':'ai_clinical',
  '/admin/users':'users','/admin/system':'system_library','/admin/offline-sync':'offline_sync','/admin/data-import':'data_import',
  '/inpatients':'inpatients','/menu':'meal_orders','/notifications':'notifications','/outside-lab':'outside_lab',
  '/financial-reports':'financial_reports','/inventory':'inventory','/stock-alerts':'stock_alerts','/patient-portal':'patient_portal',
  '/orders':'orders','/dietary-plans':'dietary_plans',
};

export const rolePermissions: Record<UserRole, Permission[]> = {
  admin: Object.values(permissionByHref),
  practitioner: ['dashboard','appointments','patients','encounters','clinical_operations','inpatient','emergency','theatre','transfusion','department_queue','radiology','radiology_results','laboratory_results','dental','procedures','anesthesia','pharmacy','medication_administration','telemedicine','fertility','ophthalmology','ai_clinical'],
  nurse: ['dashboard','patients','triage','encounters','clinical_operations','inpatient','handover','emergency','theatre','transfusion','inpatients','medication_administration','meal_orders'],
  specialist_nurse: ['dashboard','patients','appointments','triage','encounters','clinical_operations','inpatient','handover','emergency','theatre','transfusion','inpatients','medication_administration','ai_clinical'],
  midwife: ['dashboard','maternity','fertility','inpatient','handover','clinical_operations','handover','emergency','theatre','transfusion','triage','medication_administration'],
  radiologist: ['dashboard','radiology','department_queue','patients','notifications','ai_clinical'],
  front_desk: ['dashboard','patients','registration','appointments','triage','billing'],
  accountant: ['dashboard','finance','reports','billing','tariff_adjustments','claims','accounts_approvals','financial_reports','reports'],
  lab_technician: ['dashboard','department_queue','laboratory','outside_lab','reports'],
  pharmacist: ['dashboard','department_queue','pharmacy','medication_administration','inventory','stock_alerts'],
  canteen: ['dashboard','meal_orders','orders','dietary_plans'],
  patient: ['dashboard','patient_portal','appointments','telemedicine','billing'],
};

export function getDefaultPermissions(role: UserRole): Permission[] {
  return rolePermissions[role] ?? rolePermissions.patient;
}
