const DB_NAME = 'harmony-health-hub-offline';
const DB_VERSION = 4;
const STORE_NAME = 'mutation-queue';
const HISTORY_STORE_NAME = 'sync-history';
const READ_MODEL_STORE_NAME = 'read-models';
const META_STORE = 'meta';
const SYNC_EVENT = 'harmony:offline-sync';
const SYNC_LOCK_KEY = 'harmony:offline-sync-lock';
const SYNC_LOCK_TTL_MS = 30_000;
const IDEMPOTENCY_HEADER = 'x-harmony-idempotency-key';
const RETRY_BASE_DELAY_MS = 15_000;
const RETRY_MAX_DELAY_MS = 15 * 60_000;

// Direct PostgREST writes are intentionally allow-listed. Protected clinical
// workflows must use an explicit offline RPC contract rather than becoming
// offline-capable merely because they happen to use /rest/v1/.
const OFFLINE_POSTGREST_TABLES = new Set(['patients', 'triage_assessments']);

export type OfflineMutationStatus = 'pending' | 'blocked';
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
  status?: OfflineMutationStatus;
  nextAttemptAt?: string;
};
export type OfflineSyncHistory = {
  id: string;
  mutationId: string;
  idempotencyKey: string;
  event: 'queued' | 'synced' | 'failed';
  occurredAt: string;
  attempts: number;
  status?: number;
  error?: string;
};
export type OfflineReadModelKind = 'patient' | 'triage' | 'vitals' | 'appointment';
export type OfflineReadModelStatus = 'queued' | 'server-confirmed';
export type OfflineOperationEvent = {
  event: 'queued' | 'synced' | 'failed';
  mutationId: string;
  kind?: OfflineReadModelKind;
  status?: number;
  error?: string;
};
export type OfflineReadModel = {
  id: string;
  mutationId: string;
  kind: OfflineReadModelKind;
  status: OfflineReadModelStatus;
  createdAt: string;
  updatedAt: string;
  data: Record<string, unknown>;
};

const isBrowser = typeof window !== 'undefined' && typeof indexedDB !== 'undefined';
let authHeaderProvider: (() => Promise<string | undefined>) | undefined;

export function setOfflineAuthHeaderProvider(provider: () => Promise<string | undefined>): void {
  authHeaderProvider = provider;
}

function emitOfflineOperation(event: OfflineOperationEvent): void {
  if (!isBrowser) return;
  window.dispatchEvent(new CustomEvent<OfflineOperationEvent>(SYNC_EVENT, { detail: event }));
}

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (!isBrowser) return reject(new Error('IndexedDB is unavailable'));
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) db.createObjectStore(STORE_NAME, { keyPath: 'id' });
      if (!db.objectStoreNames.contains(HISTORY_STORE_NAME)) {
        const history = db.createObjectStore(HISTORY_STORE_NAME, { keyPath: 'id' });
        history.createIndex('mutationId', 'mutationId', { unique: false });
        history.createIndex('occurredAt', 'occurredAt', { unique: false });
      }
      if (!db.objectStoreNames.contains(READ_MODEL_STORE_NAME)) {
        const readModels = db.createObjectStore(READ_MODEL_STORE_NAME, { keyPath: 'id' });
        readModels.createIndex('mutationId', 'mutationId', { unique: false });
        readModels.createIndex('kind', 'kind', { unique: false });
        readModels.createIndex('updatedAt', 'updatedAt', { unique: false });
      }
      if (!db.objectStoreNames.contains(META_STORE)) db.createObjectStore(META_STORE, { keyPath: 'key' });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('Unable to open offline database'));
  });
}

async function withStore<T>(
  storeName: string,
  mode: IDBTransactionMode,
  fn: (store: IDBObjectStore) => IDBRequest | void,
): Promise<T | undefined> {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(storeName, mode);
    const request = fn(transaction.objectStore(storeName));
    transaction.oncomplete = () => resolve(request ? (request as IDBRequest).result as T : undefined);
    transaction.onerror = () => reject(transaction.error ?? new Error('Offline database transaction failed'));
  }).finally(() => db.close());
}

async function recordSyncHistory(record: Omit<OfflineSyncHistory, 'id' | 'occurredAt'>): Promise<void> {
  if (!isBrowser) return;
  await withStore(HISTORY_STORE_NAME, 'readwrite', (store) =>
    store.put({ ...record, id: crypto.randomUUID(), occurredAt: new Date().toISOString() }),
  );
}

export async function getOfflineSyncHistory(limit = 200): Promise<OfflineSyncHistory[]> {
  if (!isBrowser) return [];
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(HISTORY_STORE_NAME, 'readonly');
    const request = transaction.objectStore(HISTORY_STORE_NAME).getAll();
    request.onsuccess = () => resolve(
      (request.result as OfflineSyncHistory[])
        .sort((a, b) => b.occurredAt.localeCompare(a.occurredAt))
        .slice(0, Math.max(1, limit)),
    );
    request.onerror = () => reject(request.error ?? new Error('Unable to read offline sync history'));
    transaction.oncomplete = () => db.close();
  });
}

export async function upsertOfflineReadModel(
  model: Omit<OfflineReadModel, 'createdAt' | 'updatedAt' | 'status'> & { status?: OfflineReadModelStatus },
): Promise<OfflineReadModel> {
  const now = new Date().toISOString();
  const existing = await getOfflineReadModel(model.id);
  const next: OfflineReadModel = {
    ...model,
    status: model.status ?? existing?.status ?? 'queued',
    createdAt: existing?.createdAt ?? now,
    updatedAt: now,
  };
  await withStore(READ_MODEL_STORE_NAME, 'readwrite', (store) => store.put(next));
  window.dispatchEvent(new CustomEvent(SYNC_EVENT));
  return next;
}

export async function getOfflineReadModel(id: string): Promise<OfflineReadModel | undefined> {
  if (!isBrowser) return undefined;
  return withStore<OfflineReadModel>(READ_MODEL_STORE_NAME, 'readonly', (store) => store.get(id));
}

export async function getOfflineReadModels(kind?: OfflineReadModelKind, limit = 100): Promise<OfflineReadModel[]> {
  if (!isBrowser) return [];
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(READ_MODEL_STORE_NAME, 'readonly');
    const request = transaction.objectStore(READ_MODEL_STORE_NAME).getAll();
    request.onsuccess = () => resolve(
      (request.result as OfflineReadModel[])
        .filter((item) => !kind || item.kind === kind)
        .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
        .slice(0, Math.max(1, limit)),
    );
    request.onerror = () => reject(request.error ?? new Error('Unable to read offline continuity records'));
    transaction.oncomplete = () => db.close();
  });
}

async function markOfflineReadModelSynced(mutationId: string): Promise<void> {
  if (!isBrowser) return;
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const transaction = db.transaction(READ_MODEL_STORE_NAME, 'readwrite');
    const index = transaction.objectStore(READ_MODEL_STORE_NAME).index('mutationId');
    const request = index.getAll(mutationId);
    request.onsuccess = () => {
      const store = transaction.objectStore(READ_MODEL_STORE_NAME);
      for (const item of request.result as OfflineReadModel[]) {
        store.put({ ...item, status: 'server-confirmed', updatedAt: new Date().toISOString() });
      }
    };
    request.onerror = () => reject(request.error ?? new Error('Unable to update offline continuity status'));
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error ?? new Error('Unable to update offline continuity status'));
  }).finally(() => db.close());
}

export async function enqueueOfflineMutation(
  mutation: Omit<OfflineMutation, 'id' | 'createdAt' | 'attempts' | 'idempotencyKey' | 'status' | 'nextAttemptAt'>,
): Promise<OfflineMutation> {
  const id = crypto.randomUUID();
  const idempotencyKey = crypto.randomUUID();
  const now = new Date().toISOString();
  const headers = { ...mutation.headers, [IDEMPOTENCY_HEADER]: idempotencyKey };
  const queued: OfflineMutation = {
    ...mutation,
    headers,
    id,
    idempotencyKey,
    createdAt: now,
    attempts: 0,
    status: 'pending',
    nextAttemptAt: now,
  };
  await withStore(STORE_NAME, 'readwrite', (store) => store.put(queued));
  await recordSyncHistory({ mutationId: id, idempotencyKey, event: 'queued', attempts: 0 });
  emitOfflineOperation({ event: 'queued', mutationId: id });
  window.dispatchEvent(new CustomEvent(SYNC_EVENT));
  return queued;
}

export async function getOfflineMutations(): Promise<OfflineMutation[]> {
  if (!isBrowser) return [];
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readonly');
    const request = transaction.objectStore(STORE_NAME).getAll();
    request.onsuccess = () => resolve(
      (request.result as OfflineMutation[]).map((item) => ({
        ...item,
        status: item.status ?? 'pending',
        nextAttemptAt: item.nextAttemptAt ?? item.createdAt,
      })).sort((a, b) => a.createdAt.localeCompare(b.createdAt)),
    );
    request.onerror = () => reject(request.error ?? new Error('Unable to read offline queue'));
    transaction.oncomplete = () => db.close();
  });
}

export async function removeOfflineMutation(id: string): Promise<void> {
  await withStore(STORE_NAME, 'readwrite', (store) => store.delete(id));
}

export async function updateOfflineMutation(mutation: OfflineMutation): Promise<void> {
  await withStore(STORE_NAME, 'readwrite', (store) => store.put(mutation));
}

export async function retryOfflineMutation(id: string): Promise<boolean> {
  const item = (await getOfflineMutations()).find((mutation) => mutation.id === id);
  if (!item) return false;
  const next: OfflineMutation = {
    ...item,
    status: 'pending',
    nextAttemptAt: new Date().toISOString(),
    lastError: undefined,
  };
  await updateOfflineMutation(next);
  emitOfflineOperation({ event: 'queued', mutationId: id });
  window.dispatchEvent(new CustomEvent(SYNC_EVENT));
  return true;
}

export function isNetworkError(error: unknown): boolean {
  if (!navigator.onLine) return true;
  if (error instanceof TypeError) return true;
  return error instanceof Error && /network|fetch|failed to fetch|load failed|offline/i.test(error.message);
}

function shouldQueue(request: Request): boolean {
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(request.method)) return false;
  const url = new URL(request.url);
  if (!url.pathname.includes('/rest/v1/') || url.pathname.includes('/rpc/')) return false;
  const prefer = request.headers.get('prefer')?.toLowerCase() ?? '';
  if (prefer.includes('return=representation')) return false;
  const tableName = url.pathname.split('/rest/v1/')[1]?.split('/')[0] ?? '';
  return request.method === 'POST' && OFFLINE_POSTGREST_TABLES.has(tableName);
}

function explicitRpc(request: Request, name: string): boolean {
  return request.method === 'POST' && new URL(request.url).pathname.endsWith(`/rpc/${name}`);
}

async function requestToMutation(
  request: Request,
): Promise<Omit<OfflineMutation, 'id' | 'createdAt' | 'attempts' | 'idempotencyKey' | 'status' | 'nextAttemptAt'>> {
  const headers: Record<string, string> = {};
  request.headers.forEach((value, key) => { headers[key] = value; });
  return { url: request.url, method: request.method, headers, body: await request.clone().text() };
}

async function queueExplicitRpc(
  request: Request,
  sourceName: string,
  targetName: string,
  kind: OfflineReadModelKind,
  transform: (payload: Record<string, unknown>, id: string) => Record<string, unknown>,
): Promise<Response> {
  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(await request.clone().text()) as Record<string, unknown>;
  } catch {
    throw new Error(`Unable to safely queue the ${sourceName} request.`);
  }
  const id = crypto.randomUUID();
  const target = request.url.replace(`/rpc/${sourceName}`, `/rpc/${targetName}`);
  const queuedBody = JSON.stringify(transform(payload, id));
  const mutation = await enqueueOfflineMutation({ ...await requestToMutation(request), url: target, body: queuedBody });
  await upsertOfflineReadModel({ id, mutationId: mutation.id, kind, data: { id, ...payload, created_at: new Date().toISOString() } });
  emitOfflineOperation({ event: 'queued', mutationId: mutation.id, kind });
  return queuedResponse(mutation.id);
}

function queuedResponse(id: string): Response {
  return new Response(JSON.stringify([]), {
    status: 202,
    headers: { 'Content-Type': 'application/json', 'X-Harmony-Offline-Queued': 'true', 'X-Harmony-Offline-Queue-Id': id },
  });
}

export async function offlineAwareFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const request = new Request(input, init);
  const contracts: [string, string, OfflineReadModelKind, (payload: Record<string, unknown>, id: string) => Record<string, unknown>][] = [
    ['record_patient_vitals', 'record_patient_vitals_offline', 'vitals', (p, id) => ({ ...p, _id: id })],
    ['create_patient_appointment', 'create_patient_appointment_offline', 'appointment', (p, id) => ({ ...p, _id: id })],
  ];
  for (const [source, target, kind, transform] of contracts) {
    if (explicitRpc(request, source)) {
      if (!navigator.onLine) return queueExplicitRpc(request, source, target, kind, transform);
      try {
        return await fetch(request);
      } catch (error) {
        if (!isNetworkError(error)) throw error;
        return queueExplicitRpc(request, source, target, kind, transform);
      }
    }
  }
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
    delete headers.authorization;
    if (accessToken) headers.authorization = `Bearer ${accessToken}`;
  }
  return fetch(item.url, { method: item.method, headers, body: item.body ?? undefined });
}

function retryDelayMs(attempts: number): number {
  return Math.min(RETRY_MAX_DELAY_MS, RETRY_BASE_DELAY_MS * 2 ** Math.max(0, attempts - 1));
}

function isPermanentFailure(status: number): boolean {
  return status === 400 || status === 401 || status === 403 || status === 404 || status === 409 || (status >= 422 && status < 500);
}

function isTransientFailure(status: number): boolean {
  return status === 408 || status === 425 || status === 429 || status >= 500;
}

let syncing = false;

export async function syncOfflineMutations(): Promise<{ synced: number; remaining: number; blocked: number }> {
  if (!isBrowser || !navigator.onLine || syncing || !acquireSyncLock()) {
    const queue = await getOfflineMutations();
    return { synced: 0, remaining: queue.length, blocked: queue.filter((item) => item.status === 'blocked').length };
  }

  syncing = true;
  let synced = 0;
  try {
    const now = Date.now();
    for (const item of await getOfflineMutations()) {
      if (item.status === 'blocked') continue;
      if (item.nextAttemptAt && new Date(item.nextAttemptAt).getTime() > now) continue;
      try {
        const response = await replayMutation(item);
        if (!response.ok) {
          item.attempts += 1;
          item.lastError = `HTTP ${response.status}`;
          if (isPermanentFailure(response.status)) {
            item.status = 'blocked';
            item.nextAttemptAt = undefined;
          } else if (isTransientFailure(response.status)) {
            item.status = 'pending';
            item.nextAttemptAt = new Date(Date.now() + retryDelayMs(item.attempts)).toISOString();
          } else {
            item.status = 'pending';
            item.nextAttemptAt = new Date(Date.now() + retryDelayMs(item.attempts)).toISOString();
          }
          await updateOfflineMutation(item);
          await recordSyncHistory({ mutationId: item.id, idempotencyKey: item.idempotencyKey, event: 'failed', attempts: item.attempts, status: response.status, error: item.lastError });
          emitOfflineOperation({ event: 'failed', mutationId: item.id, status: response.status, error: item.lastError });
          if (isPermanentFailure(response.status) || isTransientFailure(response.status)) break;
          continue;
        }
        await removeOfflineMutation(item.id);
        await markOfflineReadModelSynced(item.id);
        await recordSyncHistory({ mutationId: item.id, idempotencyKey: item.idempotencyKey, event: 'synced', attempts: item.attempts + 1, status: response.status });
        emitOfflineOperation({ event: 'synced', mutationId: item.id, status: response.status });
        synced += 1;
      } catch (error) {
        item.attempts += 1;
        item.lastError = error instanceof Error ? error.message : 'Network error';
        item.status = 'pending';
        item.nextAttemptAt = new Date(Date.now() + retryDelayMs(item.attempts)).toISOString();
        await updateOfflineMutation(item);
        await recordSyncHistory({ mutationId: item.id, idempotencyKey: item.idempotencyKey, event: 'failed', attempts: item.attempts, error: item.lastError });
        emitOfflineOperation({ event: 'failed', mutationId: item.id, error: item.lastError });
        break;
      }
    }
    window.dispatchEvent(new CustomEvent(SYNC_EVENT));
    const remainingQueue = await getOfflineMutations();
    return { synced, remaining: remainingQueue.length, blocked: remainingQueue.filter((item) => item.status === 'blocked').length };
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
