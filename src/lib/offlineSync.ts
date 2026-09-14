const DB_NAME = 'harmony-health-hub-offline';
const DB_VERSION = 2;
const STORE_NAME = 'mutation-queue';
const META_STORE = 'meta';
const SYNC_EVENT = 'harmony:offline-sync';
const SYNC_LOCK_KEY = 'harmony:offline-sync-lock';
const SYNC_LOCK_TTL_MS = 30_000;
const IDEMPOTENCY_HEADER = 'x-harmony-idempotency-key';

export type OfflineMutation = {
  id: string;
  createdAt: string;
  url: string;
  method: string;
  headers: Record<string, string>;
  body: string | null;
  attempts: number;
  lastError?: string;
  idempotencyKey: string;
};

const isBrowser = typeof window !== 'undefined' && typeof indexedDB !== 'undefined';

let authHeaderProvider: (() => Promise<string | undefined>) | undefined;

export function setOfflineAuthHeaderProvider(provider: () => Promise<string | undefined>): void {
  authHeaderProvider = provider;
}

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (!isBrowser) return reject(new Error('IndexedDB is unavailable'));
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) db.createObjectStore(STORE_NAME, { keyPath: 'id' });
      if (!db.objectStoreNames.contains(META_STORE)) db.createObjectStore(META_STORE, { keyPath: 'key' });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('Unable to open offline database'));
  });
}

async function withStore<T>(mode: IDBTransactionMode, fn: (store: IDBObjectStore) => IDBRequest | void): Promise<T | undefined> {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, mode);
    const request = fn(transaction.objectStore(STORE_NAME));
    transaction.oncomplete = () => resolve(request ? (request as IDBRequest).result as T : undefined);
    transaction.onerror = () => reject(transaction.error ?? new Error('Offline database transaction failed'));
  }).finally(() => db.close());
}

export async function enqueueOfflineMutation(
  mutation: Omit<OfflineMutation, 'id' | 'createdAt' | 'attempts' | 'idempotencyKey'>,
): Promise<OfflineMutation> {
  const id = crypto.randomUUID();
  const idempotencyKey = crypto.randomUUID();
  const headers = { ...mutation.headers, [IDEMPOTENCY_HEADER]: idempotencyKey };
  const queued: OfflineMutation = {
    ...mutation,
    headers,
    id,
    idempotencyKey,
    createdAt: new Date().toISOString(),
    attempts: 0,
  };
  await withStore('readwrite', (store) => store.put(queued));
  window.dispatchEvent(new CustomEvent(SYNC_EVENT));
  return queued;
}

export async function getOfflineMutations(): Promise<OfflineMutation[]> {
  if (!isBrowser) return [];
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readonly');
    const request = transaction.objectStore(STORE_NAME).getAll();
    request.onsuccess = () => resolve((request.result as OfflineMutation[]).sort((a, b) => a.createdAt.localeCompare(b.createdAt)));
    request.onerror = () => reject(request.error ?? new Error('Unable to read offline queue'));
    transaction.oncomplete = () => db.close();
  });
}

export async function removeOfflineMutation(id: string): Promise<void> {
  await withStore('readwrite', (store) => store.delete(id));
}

export async function updateOfflineMutation(mutation: OfflineMutation): Promise<void> {
  await withStore('readwrite', (store) => store.put(mutation));
}

export function isNetworkError(error: unknown): boolean {
  if (!navigator.onLine) return true;
  if (error instanceof TypeError) return true;
  return error instanceof Error && /network|fetch|failed to fetch|load failed|offline/i.test(error.message);
}

function shouldQueue(request: Request): boolean {
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(request.method)) return false;
  const url = new URL(request.url);
  return url.pathname.includes('/rest/v1/') && !url.pathname.includes('/rpc/');
}

async function requestToMutation(request: Request): Promise<Omit<OfflineMutation, 'id' | 'createdAt' | 'attempts' | 'idempotencyKey'>> {
  const headers: Record<string, string> = {};
  request.headers.forEach((value, key) => { headers[key] = value; });
  return { url: request.url, method: request.method, headers, body: await request.clone().text() };
}

function queuedResponse(id: string): Response {
  return new Response(JSON.stringify([]), {
    status: 202,
    headers: {
      'Content-Type': 'application/json',
      'X-Harmony-Offline-Queued': 'true',
      'X-Harmony-Offline-Queue-Id': id,
    },
  });
}

export async function offlineAwareFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const request = new Request(input, init);
  if (!shouldQueue(request)) return fetch(request);

  if (!navigator.onLine) return queuedResponse((await enqueueOfflineMutation(await requestToMutation(request))).id);

  try {
    return await fetch(request);
  } catch (error) {
    if (!isNetworkError(error)) throw error;
    const queued = await enqueueOfflineMutation(await requestToMutation(request));
    return queuedResponse(queued.id);
  }
}

function acquireSyncLock(): boolean {
  if (!isBrowser) return false;
  const now = Date.now();
  const current = Number(localStorage.getItem(SYNC_LOCK_KEY) ?? '0');
  if (current > now) return false;
  localStorage.setItem(SYNC_LOCK_KEY, String(now + SYNC_LOCK_TTL_MS));
  return true;
}

function releaseSyncLock(): void {
  if (!isBrowser) return;
  localStorage.removeItem(SYNC_LOCK_KEY);
}

async function replayMutation(item: OfflineMutation): Promise<Response> {
  const headers = { ...item.headers, [IDEMPOTENCY_HEADER]: item.idempotencyKey };
  if (authHeaderProvider) {
    const accessToken = await authHeaderProvider();
    if (accessToken) headers.authorization = `Bearer ${accessToken}`;
  }
  return fetch(item.url, { method: item.method, headers, body: item.body ?? undefined });
}

let syncing = false;

export async function syncOfflineMutations(): Promise<{ synced: number; remaining: number }> {
  if (!isBrowser || !navigator.onLine || syncing || !acquireSyncLock()) {
    return { synced: 0, remaining: (await getOfflineMutations()).length };
  }

  syncing = true;
  let synced = 0;
  try {
    for (const item of await getOfflineMutations()) {
      try {
        const response = await replayMutation(item);
        if (!response.ok) {
          item.attempts += 1;
          item.lastError = `HTTP ${response.status}`;
          await updateOfflineMutation(item);
          if (response.status === 401 || response.status === 403 || response.status >= 500) break;
          continue;
        }
        await removeOfflineMutation(item.id);
        synced += 1;
      } catch (error) {
        item.attempts += 1;
        item.lastError = error instanceof Error ? error.message : 'Network error';
        await updateOfflineMutation(item);
        break;
      }
    }
    window.dispatchEvent(new CustomEvent(SYNC_EVENT));
    return { synced, remaining: (await getOfflineMutations()).length };
  } finally {
    syncing = false;
    releaseSyncLock();
  }
}

export function subscribeToOfflineSync(listener: () => void): () => void {
  window.addEventListener(SYNC_EVENT, listener);
  window.addEventListener('online', listener);
  return () => {
    window.removeEventListener(SYNC_EVENT, listener);
    window.removeEventListener('online', listener);
  };
}

export { SYNC_EVENT };
