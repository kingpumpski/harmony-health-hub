import { nextGenModules, type PlatformModuleDefinition } from './nextGenPlatform';

export interface ModuleContract {
  id: string;
  route?: string;
  existingSurface?: string;
  requiredCapabilities: string[];
  promotionChecks: string[];
}

const contracts: ModuleContract[] = [
  { id: 'empi', route: '/patients', existingSurface: 'PatientSearch/PatientHub', requiredCapabilities: ['identity', 'duplicate-detection', 'merge-audit'], promotionChecks: ['clinical-safety', 'privacy', 'RLS'] },
  { id: 'registration', route: '/patients', existingSurface: 'PatientRegistration', requiredCapabilities: ['registration', 'identity-validation', 'audit'], promotionChecks: ['privacy', 'RLS', 'audit'] },
  { id: 'consent', route: '/consent', existingSurface: 'Consent workflows', requiredCapabilities: ['consent-capture', 'withdrawal', 'versioning'], promotionChecks: ['privacy', 'RLS', 'audit'] },
  { id: 'appointments', route: '/appointments', existingSurface: 'Appointments', requiredCapabilities: ['scheduling', 'claiming', 'conflict-prevention'], promotionChecks: ['workflow', 'RLS', 'offline'] },
  { id: 'encounters', route: '/encounters', existingSurface: 'Encounters', requiredCapabilities: ['encounter-lifecycle', 'clinical-documentation'], promotionChecks: ['clinical-safety', 'audit', 'RLS'] },
  { id: 'pharmacy', route: '/pharmacy', existingSurface: 'Pharmacy', requiredCapabilities: ['prescribing', 'dispensing', 'inventory'], promotionChecks: ['medication-safety', 'RLS', 'audit'] },
  { id: 'medication-administration', route: '/pharmacy/medication-administration', existingSurface: 'MedicationAdministration', requiredCapabilities: ['five-rights', 'barcode-or-identity-check', 'administration-audit'], promotionChecks: ['medication-safety', 'clinical-safety', 'audit'] },
  { id: 'laboratory', route: '/laboratory', existingSurface: 'Laboratory', requiredCapabilities: ['orders', 'results', 'QC', 'device-ingestion'], promotionChecks: ['interoperability', 'clinical-safety', 'audit'] },
  { id: 'imaging', route: '/imaging', existingSurface: 'Imaging', requiredCapabilities: ['orders', 'reports', 'DICOM-boundary'], promotionChecks: ['interoperability', 'clinical-safety', 'audit'] },
  { id: 'device-integration', existingSurface: 'Platform runtime', requiredCapabilities: ['registry', 'protocol-boundary', 'QC', 'lifecycle'], promotionChecks: ['interoperability', 'clinical-safety', 'security'] },
  { id: 'blood-bank', route: '/blood-bank', existingSurface: 'Transfusion workflows', requiredCapabilities: ['compatibility', 'traceability', 'administration-safety'], promotionChecks: ['clinical-safety', 'offline-safety', 'audit'] },
  { id: 'admissions', route: '/admissions', existingSurface: 'Admissions', requiredCapabilities: ['admission-lifecycle', 'transfer', 'discharge'], promotionChecks: ['clinical-safety', 'RLS', 'audit'] },
  { id: 'wards-beds', route: '/wards', existingSurface: 'Ward/Bed Board', requiredCapabilities: ['bed-state', 'occupancy', 'assignment'], promotionChecks: ['concurrency', 'RLS', 'audit'] },
  { id: 'nursing-care', route: '/nursing', existingSurface: 'Nursing workflows', requiredCapabilities: ['handover', 'care-tasks', 'escalation'], promotionChecks: ['clinical-safety', 'downtime', 'audit'] },
  { id: 'emergency', route: '/emergency', existingSurface: 'Emergency Board', requiredCapabilities: ['triage', 'acuity', 'escalation'], promotionChecks: ['clinical-safety', 'performance', 'audit'] },
  { id: 'theatre', route: '/theatre', existingSurface: 'Theatre Board', requiredCapabilities: ['case-lifecycle', 'safety-checks', 'team-readiness'], promotionChecks: ['clinical-safety', 'audit', 'RLS'] },
  { id: 'anesthesia', route: '/theatre/anesthesia', existingSurface: 'Anesthetic assessment', requiredCapabilities: ['pre-op-assessment', 'monitoring', 'recovery'], promotionChecks: ['clinical-safety', 'audit', 'RLS'] },
  { id: 'maternity', route: '/maternity', existingSurface: 'Maternity', requiredCapabilities: ['maternal-care', 'labor-lifecycle', 'newborn-linkage'], promotionChecks: ['clinical-safety', 'privacy', 'audit'] },
  { id: 'fertility', route: '/fertility', existingSurface: 'Fertility', requiredCapabilities: ['cycle-workflow', 'consent', 'procedure-traceability'], promotionChecks: ['clinical-safety', 'privacy', 'audit'] },
  { id: 'dental', route: '/dental', existingSurface: 'Dental', requiredCapabilities: ['dental-charting', 'treatment-plan', 'imaging-linkage'], promotionChecks: ['clinical-safety', 'audit', 'RLS'] },
  { id: 'ophthalmology', route: '/ophthalmology', existingSurface: 'Ophthalmology', requiredCapabilities: ['eye-exam', 'laterality', 'procedure-traceability'], promotionChecks: ['clinical-safety', 'audit', 'RLS'] },
  { id: 'telemedicine', route: '/telemedicine', existingSurface: 'Telemedicine', requiredCapabilities: ['identity', 'consent', 'session-continuity'], promotionChecks: ['privacy', 'security', 'clinical-safety'] },
  { id: 'referrals', route: '/referrals', existingSurface: 'Referral workflows', requiredCapabilities: ['referral-lifecycle', 'clinical-context', 'acknowledgement'], promotionChecks: ['clinical-safety', 'interoperability', 'audit'] },
  { id: 'care-plans', route: '/care-plans', existingSurface: 'Care planning', requiredCapabilities: ['goals', 'tasks', 'review-cycle'], promotionChecks: ['clinical-safety', 'privacy', 'audit'] },
  { id: 'billing', route: '/billing', existingSurface: 'Billing', requiredCapabilities: ['invoice', 'payment', 'financial-audit'], promotionChecks: ['financial-integrity', 'RLS', 'audit'] },
  { id: 'claims', route: '/insurance-claims', existingSurface: 'InsuranceClaims', requiredCapabilities: ['authorization', 'adjudication', 'reconciliation'], promotionChecks: ['financial-integrity', 'audit', 'idempotency'] },
  { id: 'inventory', route: '/inventory', existingSurface: 'Inventory', requiredCapabilities: ['stock-ledger', 'lot-traceability', 'reconciliation'], promotionChecks: ['financial-integrity', 'audit', 'concurrency'] },
  { id: 'workforce', route: '/roster', existingSurface: 'Roster/Shift Management', requiredCapabilities: ['rostering', 'availability', 'capacity'], promotionChecks: ['authorization', 'continuity', 'audit'] },
  { id: 'procurement', existingSurface: 'HMS procurement foundation', requiredCapabilities: ['suppliers', 'purchase-orders', 'approval', 'receiving-reconciliation'], promotionChecks: ['financial-integrity', 'audit', 'RLS'] },
  { id: 'asset-biomedical', existingSurface: 'HMS biomedical asset foundation', requiredCapabilities: ['asset-register', 'maintenance', 'calibration', 'lifecycle'], promotionChecks: ['safety', 'audit', 'RLS'] },
  { id: 'physiotherapy', existingSurface: 'HMS physiotherapy foundation', requiredCapabilities: ['assessment', 'care-plan-linkage', 'session-documentation'], promotionChecks: ['clinical-safety', 'RLS', 'audit'] },
  { id: 'dietary-restaurant', route: '/menu', existingSurface: 'CanteenMeals', requiredCapabilities: ['dietary-plan', 'meal-order', 'delivery'], promotionChecks: ['clinical-safety', 'privacy', 'audit'] },
  { id: 'reports', route: '/reports', existingSurface: 'Reports Center', requiredCapabilities: ['operational-reporting', 'export', 'traceability'], promotionChecks: ['privacy', 'performance', 'audit'] },
  { id: 'report-centre', route: '/reports', existingSurface: 'ReportsCenter/ReportsSubmissionDashboard', requiredCapabilities: ['template-library', 'scheduled-runs', 'submission-tracking', 'multi-format-export'], promotionChecks: ['privacy', 'performance', 'audit'] },
  { id: 'data-import', route: '/admin/data-import', existingSurface: 'DataImport/BulkUpload', requiredCapabilities: ['templates', 'staging', 'validation', 'quarantine', 'atomic-commit', 'rollback'], promotionChecks: ['integrity', 'RLS', 'audit'] },
  { id: 'teaching-research', existingSurface: 'HMS teaching/research foundation', requiredCapabilities: ['project-governance', 'dataset-request', 'de-identification', 'retention'], promotionChecks: ['privacy', 'ethics', 'audit'] },
  { id: 'public-health', route: '/public-health', existingSurface: 'Reporting foundation', requiredCapabilities: ['surveillance', 'aggregation', 'jurisdictional-export'], promotionChecks: ['privacy', 'jurisdiction', 'audit'] },
  { id: 'patient-engagement', route: '/patient-portal', existingSurface: 'PatientPortal/PatientChat', requiredCapabilities: ['consent', 'channel-preferences', 'accessibility'], promotionChecks: ['privacy', 'accessibility', 'audit'] },
  { id: 'messaging', route: '/messages', existingSurface: 'Chat/Portal messaging', requiredCapabilities: ['threading', 'consent', 'minimum-necessary'], promotionChecks: ['privacy', 'security', 'audit'] },
  { id: 'notifications', existingSurface: 'notifications service', requiredCapabilities: ['queueing', 'delivery', 'preferences'], promotionChecks: ['consent', 'resilience', 'audit'] },
  { id: 'interoperability', existingSurface: 'Platform runtime', requiredCapabilities: ['envelope', 'idempotency', 'retry', 'quarantine', 'replay'], promotionChecks: ['security', 'resilience', 'observability'] },
  { id: 'terminology', existingSurface: 'Terminology boundaries', requiredCapabilities: ['code-systems', 'versioning', 'validation'], promotionChecks: ['clinical-safety', 'interoperability', 'audit'] },
  { id: 'audit', existingSurface: 'Existing audit/logging foundations', requiredCapabilities: ['append-only', 'actor-context', 'trace-correlation'], promotionChecks: ['security', 'privacy', 'integrity'] },
  { id: 'configuration', route: '/admin', existingSurface: 'Admin configuration', requiredCapabilities: ['versioned-config', 'jurisdiction-profile', 'change-control'], promotionChecks: ['RLS', 'audit', 'deployment'] },
  { id: 'user-role-management', route: '/admin/roles', existingSurface: 'AdminUsers/RolePermissions', requiredCapabilities: ['role-catalogue', 'module-permission-matrix', 'least-privilege'], promotionChecks: ['RLS', 'security', 'audit'] },
  { id: 'ai-clinical-hub', route: '/ai-clinical', existingSurface: 'AIClinicalHub', requiredCapabilities: ['model-governance', 'provenance', 'human-review'], promotionChecks: ['AI-safety', 'privacy', 'audit'] },
  { id: 'ai-governance', existingSurface: 'Platform runtime', requiredCapabilities: ['model-registry', 'evaluation-evidence', 'intended-use-controls'], promotionChecks: ['AI-safety', 'privacy', 'audit'] },
  { id: 'accessibility', existingSurface: 'Accessibility preferences/design system', requiredCapabilities: ['WCAG-2.2-AA', 'keyboard', 'screen-reader'], promotionChecks: ['accessibility', 'usability', 'regression'] },
];

export function getModuleContract(id: string): ModuleContract | undefined {
  return contracts.find((contract) => contract.id === id);
}

export function getModuleContracts(): readonly ModuleContract[] {
  return contracts;
}

export function getUncontractedModules(): PlatformModuleDefinition[] {
  const known = new Set(contracts.map((contract) => contract.id));
  return nextGenModules.filter((module) => !known.has(module.id));
}
