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

export const nextGenModules: PlatformModuleDefinition[] = [
  { id: 'empi', domain: 'patient', tier: 'core', safetyCritical: true, offlineCapable: true, state: 'available' },
  { id: 'registration', domain: 'patient', tier: 'core', safetyCritical: true, offlineCapable: true, state: 'available' },
  { id: 'consent', domain: 'privacy', tier: 'core', safetyCritical: true, offlineCapable: true, state: 'available' },
  { id: 'encounters', domain: 'clinical', tier: 'clinical', safetyCritical: true, offlineCapable: true, state: 'available' },
  { id: 'laboratory', domain: 'diagnostics', tier: 'clinical', safetyCritical: true, offlineCapable: false, state: 'available' },
  { id: 'imaging', domain: 'diagnostics', tier: 'clinical', safetyCritical: true, offlineCapable: false, state: 'available' },
  { id: 'pharmacy', domain: 'medication', tier: 'clinical', safetyCritical: true, offlineCapable: true, state: 'available' },
  { id: 'maternity', domain: 'clinical', tier: 'clinical', safetyCritical: true, offlineCapable: true, state: 'available' },
  { id: 'fertility', domain: 'clinical', tier: 'clinical', safetyCritical: true, offlineCapable: true, state: 'available' },
  { id: 'billing', domain: 'revenue', tier: 'enterprise', safetyCritical: false, offlineCapable: true, state: 'available' },
  { id: 'claims', domain: 'revenue', tier: 'enterprise', safetyCritical: true, offlineCapable: true, state: 'available' },
  { id: 'inventory', domain: 'supply-chain', tier: 'enterprise', safetyCritical: true, offlineCapable: true, state: 'available' },
  { id: 'workforce', domain: 'workforce', tier: 'enterprise', safetyCritical: false, offlineCapable: true, state: 'planned' },
  { id: 'public-health', domain: 'population', tier: 'enterprise', safetyCritical: true, offlineCapable: false, state: 'planned' },
  { id: 'interoperability', domain: 'integration', tier: 'enterprise', safetyCritical: true, offlineCapable: false, state: 'validated' },
  { id: 'device-integration', domain: 'integration', tier: 'enterprise', safetyCritical: true, offlineCapable: false, state: 'validated' },
  { id: 'patient-engagement', domain: 'experience', tier: 'experience', safetyCritical: false, offlineCapable: true, state: 'available' },
  { id: 'accessibility', domain: 'experience', tier: 'experience', safetyCritical: false, offlineCapable: true, state: 'validated' },
  { id: 'ai-clinical-hub', domain: 'clinical-intelligence', tier: 'clinical', safetyCritical: true, offlineCapable: false, state: 'available' },
  { id: 'ai-governance', domain: 'clinical-intelligence', tier: 'enterprise', safetyCritical: true, offlineCapable: false, state: 'validated' },
  { id: 'audit', domain: 'security', tier: 'core', safetyCritical: true, offlineCapable: true, state: 'available' },
];

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
