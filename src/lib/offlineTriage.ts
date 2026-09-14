import { enqueueOfflineMutation, upsertOfflineReadModel } from '@/lib/offlineSync';
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
 * Triage uses a stable client UUID and PostgREST's primary-key conflict-safe
 * insert semantics. If synchronization reaches the server but its response
 * is lost, replaying the same assessment is therefore a no-op.
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

  const queued = await enqueueOfflineMutation({
    url: `${SUPABASE_URL}/rest/v1/triage_assessments?on_conflict=id`,
    method: 'POST',
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      authorization: `Bearer ${data.session.access_token}`,
      'content-type': 'application/json',
      prefer: 'resolution=ignore-duplicates,return=minimal',
    },
    body: JSON.stringify(stableRow),
  });

  await upsertOfflineReadModel({
    id,
    mutationId: queued.id,
    kind: 'triage',
    data: stableRow,
  });

  return { id, patientId, row: stableRow };
}
