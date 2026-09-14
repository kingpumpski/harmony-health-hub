import { enqueueOfflineMutation } from '@/lib/offlineSync';
import { supabase } from '@/integrations/supabase/client';

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
 * and uses a primary-key conflict-safe PostgREST write. A replay after a lost
 * response therefore becomes a no-op instead of creating a second patient.
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

  const { data, error } = await supabase.auth.getSession();
  if (error || !data.session?.access_token) {
    throw new Error('You must be signed in to save an offline patient registration.');
  }

  await enqueueOfflineMutation({
    url: `${SUPABASE_URL}/rest/v1/patients?on_conflict=id`,
    method: 'POST',
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      authorization: `Bearer ${data.session.access_token}`,
      'content-type': 'application/json',
      prefer: 'resolution=ignore-duplicates,return=minimal',
    },
    body: JSON.stringify(stableRow),
  });

  return { id, patientCode, row: stableRow };
}
