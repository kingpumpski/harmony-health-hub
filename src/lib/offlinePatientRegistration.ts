import { enqueueOfflineMutation } from '@/lib/offlineSync';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL?.trim() || 'https://ygqoptvezotdqhtimdkr.supabase.co';
const SUPABASE_PUBLISHABLE_KEY =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ||
  'sb_publishable_OWOl70nV57PKXtYPEtOvKg_mpTloQrH';

export type OfflinePatientRegistration = {
  id: string;
  patientCode: string;
  row: Record<string, unknown>;
};

/**
 * Explicit offline command for patient registration.
 *
 * Unlike the generic PostgREST interceptor, this command supplies stable IDs
 * and uses return=minimal, so the queued write does not pretend to have an
 * authoritative server response. The patient identifier is therefore known
 * before synchronization and remains stable across retries.
 */
export async function queueOfflinePatientRegistration(
  row: Record<string, unknown>,
): Promise<OfflinePatientRegistration> {
  const id = String(row.id || crypto.randomUUID());
  const patientCode = String(
    row.patient_code ||
      `OFF-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}-${id.replace(/-/g, '').slice(0, 8).toUpperCase()}`,
  );
  const stableRow = { ...row, id, patient_code: patientCode };

  const session = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      authorization: `Bearer ${await getAccessToken()}`,
    },
  });
  if (!session.ok) {
    throw new Error('Your session could not be verified. Sign in again before saving an offline patient registration.');
  }

  const token = await getAccessToken();
  if (!token) throw new Error('You must be signed in to save an offline patient registration.');

  await enqueueOfflineMutation({
    url: `${SUPABASE_URL}/rest/v1/patients`,
    method: 'POST',
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      prefer: 'return=minimal',
    },
    body: JSON.stringify(stableRow),
  });

  return { id, patientCode, row: stableRow };
}

async function getAccessToken(): Promise<string> {
  const storageKeys = Object.keys(localStorage).filter((key) => key.startsWith('sb-') && key.endsWith('-auth-token'));
  for (const key of storageKeys) {
    try {
      const parsed = JSON.parse(localStorage.getItem(key) || 'null') as { access_token?: string } | null;
      if (parsed?.access_token) return parsed.access_token;
    } catch {
      // Continue searching for the brokered Supabase session key.
    }
  }
  return '';
}
