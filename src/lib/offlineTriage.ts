import { enqueueOfflineMutation } from '@/lib/offlineSync';
import { supabase } from '@/integrations/supabase/client';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL?.trim() || 'https://ygqoptvezotdqhtimdkr.supabase.co';
const SUPABASE_PUBLISHABLE_KEY =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ||
  'sb_publishable_OWOl70nV57PKXtYPEtOvKg_mpTloQrH';

export type OfflineTriageAssessment = {
  id: string;
  patientId: string;
  row: Record<string, unknown>;
};

/**
 * Explicit offline triage command.
 *
 * Triage is only accepted offline as a structured assessment with a
 * client-generated stable UUID. It is queued with return=minimal so the UI
 * never treats a synthetic response as a server-authoritative clinical row.
 * The server remains authoritative when synchronization occurs.
 */
export async function queueOfflineTriageAssessment(
  row: Record<string, unknown>,
): Promise<OfflineTriageAssessment> {
  const patientId = String(row.patient_id || '');
  if (!patientId) throw new Error('A patient is required for offline triage.');

  const id = String(row.id || crypto.randomUUID());
  const stableRow = {
    ...row,
    id,
    patient_id: patientId,
  };

  const { data, error } = await supabase.auth.getSession();
  if (error || !data.session?.access_token) {
    throw new Error('You must be signed in to save an offline triage assessment.');
  }

  await enqueueOfflineMutation({
    url: `${SUPABASE_URL}/rest/v1/triage_assessments`,
    method: 'POST',
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      authorization: `Bearer ${data.session.access_token}`,
      'content-type': 'application/json',
      prefer: 'return=minimal',
    },
    body: JSON.stringify(stableRow),
  });

  return { id, patientId, row: stableRow };
}
