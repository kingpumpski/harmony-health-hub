export const NEXT_GEN_FACILITY_CONTEXT_KEY = 'harmony:nextgen:facility-context';

export function getNextGenFacilityContext(): string | null {
  if (typeof window === 'undefined') return null;
  const value = window.localStorage.getItem(NEXT_GEN_FACILITY_CONTEXT_KEY);
  return value?.trim() || null;
}

export function setNextGenFacilityContext(facilityId: string | null): void {
  if (typeof window === 'undefined') return;
  if (facilityId) window.localStorage.setItem(NEXT_GEN_FACILITY_CONTEXT_KEY, facilityId);
  else window.localStorage.removeItem(NEXT_GEN_FACILITY_CONTEXT_KEY);
}
