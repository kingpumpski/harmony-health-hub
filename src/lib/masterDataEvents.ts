export type MasterDataDomain =
  | 'wards'
  | 'beds'
  | 'lab_tests'
  | 'tariffs'
  | 'services'
  | 'patients'
  | 'providers'
  | 'pharmacy'
  | 'diagnoses'
  | 'all';

const EVENT_NAME = 'harmony:master-data-changed';

export function notifyMasterDataChanged(domain: MasterDataDomain) {
  if (typeof window === 'undefined') return;
  const detail = { domain, at: Date.now() };
  window.dispatchEvent(new CustomEvent(EVENT_NAME, { detail }));
  try {
    window.localStorage.setItem(EVENT_NAME, JSON.stringify(detail));
  } catch {
    // Storage may be unavailable in private/restricted browser contexts.
  }
}

export function subscribeMasterDataChanged(
  domains: MasterDataDomain[],
  onChange: (domain: MasterDataDomain) => void,
) {
  if (typeof window === 'undefined') return () => undefined;

  const accepts = (domain: MasterDataDomain) =>
    domains.includes('all') || domains.includes(domain) || domain === 'all';

  const handleEvent = (event: Event) => {
    const domain = (event as CustomEvent<{ domain?: MasterDataDomain }>).detail?.domain;
    if (domain && accepts(domain)) onChange(domain);
  };

  const handleStorage = (event: StorageEvent) => {
    if (event.key !== EVENT_NAME || !event.newValue) return;
    try {
      const parsed = JSON.parse(event.newValue) as { domain?: MasterDataDomain };
      if (parsed.domain && accepts(parsed.domain)) onChange(parsed.domain);
    } catch {
      // Ignore malformed cross-tab notifications.
    }
  };

  window.addEventListener(EVENT_NAME, handleEvent);
  window.addEventListener('storage', handleStorage);
  return () => {
    window.removeEventListener(EVENT_NAME, handleEvent);
    window.removeEventListener('storage', handleStorage);
  };
}
