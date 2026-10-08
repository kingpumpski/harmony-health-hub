import { lazy, type ComponentType } from 'react';

const RECOVERY_QUERY = '__hms_chunk_recovery';
const RECOVERY_PREFIX = 'hms-chunk-recovery:';

function isChunkLoadFailure(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return /failed to fetch dynamically imported module|loading chunk|chunkloaderror|importing a module script failed|failed to fetch/i.test(message);
}

export function lazyWithChunkRecovery<T extends ComponentType<unknown>>(
  loader: () => Promise<{ default: T }>,
) {
  return lazy(async () => {
    try {
      const module = await loader();

      if (typeof window !== 'undefined') {
        sessionStorage.removeItem(RECOVERY_PREFIX + window.location.pathname);

        const url = new URL(window.location.href);
        if (url.searchParams.has(RECOVERY_QUERY)) {
          url.searchParams.delete(RECOVERY_QUERY);
          window.history.replaceState(window.history.state, '', url.toString());
        }
      }

      return module;
    } catch (error) {
      if (typeof window === 'undefined' || !isChunkLoadFailure(error)) throw error;

      const recoveryKey = RECOVERY_PREFIX + window.location.pathname;
      if (sessionStorage.getItem(recoveryKey) === '1') {
        sessionStorage.removeItem(recoveryKey);
        throw error;
      }

      sessionStorage.setItem(recoveryKey, '1');

      // GitHub Pages replaces the complete static artifact on deployment.
      // A cached HTML shell can therefore reference a removed Vite hash.
      // Reload once with a cache-busting query so the browser obtains the
      // current index.html and its current hashed asset graph.
      const url = new URL(window.location.href);
      url.searchParams.set(RECOVERY_QUERY, String(Date.now()));
      window.location.replace(url.toString());

      return new Promise<never>(() => undefined);
    }
  });
}
