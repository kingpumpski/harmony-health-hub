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
  { id: 'appointments', route: '/appointments', existingSurface: 'Appointments', requiredCapabilities: ['scheduling', 'claiming', 'conflict-prevention'], promotionChecks: ['workflow', 'RLS', 'offline'] },
  { id: 'encounters', route: '/encounters', existingSurface: 'Encounters', requiredCapabilities: ['encounter-lifecycle', 'clinical-documentation'], promotionChecks: ['clinical-safety', 'audit', 'RLS'] },
  { id: 'laboratory', route: '/laboratory', existingSurface: 'Laboratory', requiredCapabilities: ['orders', 'results', 'QC', 'device-ingestion'], promotionChecks: ['interoperability', 'clinical-safety', 'audit'] },
  { id: 'imaging', route: '/imaging', existingSurface: 'Imaging', requiredCapabilities: ['orders', 'reports', 'DICOM-boundary'], promotionChecks: ['interoperability', 'clinical-safety', 'audit'] },
  { id: 'pharmacy', route: '/pharmacy', existingSurface: 'Pharmacy', requiredCapabilities: ['prescribing', 'dispensing', 'inventory'], promotionChecks: ['medication-safety', 'RLS', 'audit'] },
  { id: 'billing', route: '/billing', existingSurface: 'Billing', requiredCapabilities: ['invoice', 'payment', 'financial-audit'], promotionChecks: ['financial-integrity', 'RLS', 'audit'] },
  { id: 'claims', route: '/insurance-claims', existingSurface: 'InsuranceClaims', requiredCapabilities: ['authorization', 'adjudication', 'reconciliation'], promotionChecks: ['financial-integrity', 'audit', 'idempotency'] },
  { id: 'ai-clinical-hub', route: '/ai-clinical', existingSurface: 'AIClinicalHub', requiredCapabilities: ['model-governance', 'provenance', 'human-review'], promotionChecks: ['AI-safety', 'privacy', 'audit'] },
  { id: 'patient-engagement', route: '/patient-portal', existingSurface: 'PatientPortal/PatientChat', requiredCapabilities: ['consent', 'channel-preferences', 'accessibility'], promotionChecks: ['privacy', 'accessibility', 'audit'] },
  { id: 'interoperability', existingSurface: 'Platform runtime', requiredCapabilities: ['envelope', 'idempotency', 'retry', 'quarantine', 'replay'], promotionChecks: ['security', 'resilience', 'observability'] },
  { id: 'device-integration', existingSurface: 'Platform runtime', requiredCapabilities: ['registry', 'protocol-boundary', 'QC', 'lifecycle'], promotionChecks: ['interoperability', 'clinical-safety', 'security'] },
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
