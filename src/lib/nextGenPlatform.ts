export type PlatformModuleTier = 'core' | 'clinical' | 'enterprise' | 'experience';
export type PlatformModuleState = 'planned' | 'available' | 'disabled' | 'validated';

export interface PlatformModuleDefinition {
  id: string;
  domain: string;
  tier: PlatformModuleTier;
  safetyCritical: boolean;
  offlineCapable: boolean;
  state: PlatformModuleState;
}

export interface AccessibilityPreferences {
  textScale: '100' | '110' | '125' | '150';
  highContrast: boolean;
  reducedMotion: boolean;
  captions: boolean;
  readAloud: boolean;
  voiceNavigation: boolean;
}

const MODULE_STATE_KEY = 'harmony:nextgen:module-state';
const ACCESSIBILITY_KEY = 'harmony:accessibility:preferences';

const defaultAccessibility: AccessibilityPreferences = {
  textScale: '100', highContrast: false, reducedMotion: false, captions: true, readAloud: false, voiceNavigation: false,
};

const registry = [
  ['empi','patient','high','limited'],['registration','patient','high','stageable'],['consent','governance','high','restricted'],
  ['appointments','clinical','high','stageable'],['encounters','clinical','critical','restricted'],['pharmacy','clinical','critical','restricted'],
  ['medication-administration','clinical','critical','restricted'],['laboratory','diagnostics','critical','limited'],['imaging','diagnostics','critical','limited'],
  ['device-integration','interoperability','critical','gateway'],['blood-bank','diagnostics','critical','restricted'],['admissions','inpatient','high','limited'],
  ['wards-beds','inpatient','high','limited'],['nursing-care','inpatient','critical','restricted'],['emergency','emergency','critical','restricted'],
  ['theatre','procedures','critical','restricted'],['anesthesia','procedures','critical','restricted'],['maternity','specialty','critical','restricted'],
  ['fertility','specialty','critical','restricted'],['dental','specialty','high','limited'],['ophthalmology','specialty','high','limited'],
  ['telemedicine','virtual-care','high','stageable'],['referrals','care-coordination','high','stageable'],['care-plans','care-coordination','high','limited'],
  ['billing','revenue','high','restricted'],['claims','revenue','high','stageable'],['inventory','operations','high','limited'],
  ['procurement','operations','high','restricted'],['asset-biomedical','operations','high','restricted'],['workforce','operations','medium','stageable'],
  ['physiotherapy','clinical','high','limited'],['dietary-restaurant','ancillary','medium','stageable'],['reports','analytics','high','read-only'],
  ['report-centre','analytics','high','read-only'],['public-health','population','high','stageable'],['data-import','migration','high','restricted'],
  ['teaching-research','education','high','restricted'],['patient-engagement','engagement','high','stageable'],['messaging','engagement','high','limited'],
  ['notifications','platform','high','queueable'],['interoperability','platform','critical','gateway'],['terminology','platform','high','read-only'],
  ['audit','platform','critical','append-only'],['configuration','platform','critical','restricted'],['user-role-management','governance','critical','restricted'],
  ['ai-clinical-hub','intelligence','critical','restricted'],['ai-governance','governance','critical','restricted'],['hr-payroll','enterprise','high','stageable'],
  ['icu-critical-care','clinical','critical','restricted'],['mental-health','clinical','high','restricted'],['social-work','care-coordination','high','stageable'],
  ['quality-compliance','governance','high','restricted'],['infection-control','governance','high','restricted'],['mortuary','support','high','restricted'],
  ['ambulance','emergency','high','restricted'],['research-portal','education','high','restricted'],['external-audit','governance','high','read-only'],
  ['genomics','diagnostics','critical','restricted'],['accessibility','experience','high','local'],
] as const;

function inferTier(domain: string): PlatformModuleTier {
  if (['patient','governance','platform'].includes(domain)) return 'core';
  if (['clinical','diagnostics','inpatient','emergency','procedures','specialty','virtual-care','care-coordination','intelligence'].includes(domain)) return 'clinical';
  if (['engagement','experience'].includes(domain)) return 'experience';
  return 'enterprise';
}

const available = new Set(registry.map(([id]) => id));
const validated = new Set(['interoperability','device-integration','accessibility','ai-governance']);

export const nextGenModules: PlatformModuleDefinition[] = registry.map(([id, domain, safety, offline]) => ({
  id, domain, tier: inferTier(domain), safetyCritical: safety === 'critical',
  offlineCapable: !['restricted','gateway'].includes(offline),
  state: validated.has(id) ? 'validated' : available.has(id) ? 'available' : 'planned',
}));

export function isModuleEnabled(id: string): boolean {
  const module = nextGenModules.find((item) => item.id === id);
  if (!module || module.state === 'planned' || typeof window === 'undefined') return false;
  const stored = window.localStorage.getItem(MODULE_STATE_KEY);
  if (!stored) return module.state !== 'disabled';
  try { return (JSON.parse(stored) as Record<string, boolean>)[id] ?? module.state !== 'disabled'; }
  catch { return module.state !== 'disabled'; }
}

export function setModuleEnabled(id: string, enabled: boolean): void {
  const module = nextGenModules.find((item) => item.id === id);
  if (!module || module.state === 'planned' || typeof window === 'undefined') return;
  let state: Record<string, boolean> = {};
  const stored = window.localStorage.getItem(MODULE_STATE_KEY);
  if (stored) { try { state = JSON.parse(stored) as Record<string, boolean>; } catch { state = {}; } }
  state[id] = enabled;
  window.localStorage.setItem(MODULE_STATE_KEY, JSON.stringify(state));
}

export function getAccessibilityPreferences(): AccessibilityPreferences {
  if (typeof window === 'undefined') return defaultAccessibility;
  const stored = window.localStorage.getItem(ACCESSIBILITY_KEY);
  if (!stored) return defaultAccessibility;
  try { return { ...defaultAccessibility, ...(JSON.parse(stored) as Partial<AccessibilityPreferences>) }; }
  catch { return defaultAccessibility; }
}

export function setAccessibilityPreferences(preferences: AccessibilityPreferences): void {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(ACCESSIBILITY_KEY, JSON.stringify(preferences));
  applyAccessibilityPreferences(preferences);
}

export function applyAccessibilityPreferences(preferences = getAccessibilityPreferences()): void {
  if (typeof document === 'undefined') return;
  document.documentElement.dataset.textScale = preferences.textScale;
  document.documentElement.toggleAttribute('data-high-contrast', preferences.highContrast);
  document.documentElement.toggleAttribute('data-reduced-motion', preferences.reducedMotion);
}
