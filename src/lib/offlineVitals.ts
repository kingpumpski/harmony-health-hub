import { enqueueOfflineMutation, upsertOfflineReadModel } from '@/lib/offlineSync';
import { supabase } from '@/integrations/supabase/client';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL?.trim() || 'https://ygqoptvezotdqhtimdkr.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() || 'sb_publishable_OWOl70nV57PKXtYPEtOvKg_mpTloQrH';

export type OfflineVitalSigns = {
  id: string;
  patientId: string;
  row: Record<string, unknown>;
};

export async function queueOfflineVitalSigns(row: Record<string, unknown>): Promise<OfflineVitalSigns> {
  const patientId = String(row.patient_id || '');
  if (!patientId) throw new Error('A patient is required for offline vital signs.');
  const id = String(row.id || crypto.randomUUID());
  const stableRow = { ...row, id, patient_id: patientId };
  const { data, error } = await supabase.auth.getSession();
  if (error || !data.session?.access_token) throw new Error('You must be signed in to save offline vital signs.');

  const mutation = await enqueueOfflineMutation({
    url: `${SUPABASE_URL}/rest/v1/rpc/record_patient_vitals_offline`,
    method: 'POST',
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      authorization: `Bearer ${data.session.access_token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      _id: id,
      _patient_id: patientId,
      _appointment_id: stableRow.appointment_id ?? null,
      _temperature: stableRow.temperature ?? null,
      _pulse: stableRow.pulse_rate ?? null,
      _systolic: stableRow.systolic ?? null,
      _diastolic: stableRow.diastolic ?? null,
      _respiratory_rate: stableRow.respiratory_rate ?? null,
      _oxygen_saturation: stableRow.oxygen_saturation ?? null,
      _weight_kg: stableRow.weight_kg ?? null,
      _height_cm: stableRow.height_cm ?? null,
      _notes: stableRow.notes ?? null,
      _recorded_at: stableRow.recorded_at ?? new Date().toISOString(),
    }),
  });

  await upsertOfflineReadModel({
    id,
    mutationId: mutation.id,
    kind: 'vitals',
    data: stableRow,
  });
  return { id, patientId, row: stableRow };
}
