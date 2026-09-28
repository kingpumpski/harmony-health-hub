import { supabase } from '@/integrations/supabase/client';

export type OfflineTriageAssessment = {
  id: string;
  patientId: string;
  row: Record<string, unknown>;
};

/**
 * Queue triage through the authenticated triage RPC.
 * offlineAwareFetch converts that RPC to the explicit idempotent offline RPC
 * when connectivity is unavailable; triage never falls back to direct table DML.
 */
export async function queueOfflineTriageAssessment(
  row: Record<string, unknown>,
): Promise<OfflineTriageAssessment> {
  const patientId = String(row.patient_id || row._patient_id || '');
  if (!patientId) throw new Error('A patient is required for offline triage.');

  const payload = {
    _patient_id: patientId,
    _systolic: row.systolic ?? row._systolic ?? null,
    _diastolic: row.diastolic ?? row._diastolic ?? null,
    _heart_rate: row.heart_rate ?? row._heart_rate ?? null,
    _temperature: row.temperature ?? row._temperature ?? null,
    _respiratory_rate: row.respiratory_rate ?? row._respiratory_rate ?? null,
    _oxygen_saturation: row.oxygen_saturation ?? row._oxygen_saturation ?? null,
    _weight_kg: row.weight_kg ?? row._weight_kg ?? null,
    _height_m: row.height_m ?? row._height_m ?? null,
    _pain_score: row.pain_score ?? row._pain_score ?? null,
    _consciousness: row.consciousness ?? row._consciousness ?? null,
    _presenting_complaint: row.presenting_complaint ?? row._presenting_complaint ?? null,
    _clinical_notes: row.clinical_notes ?? row._clinical_notes ?? null,
    _priority: row.priority ?? row._priority ?? 'routine',
  };

  const { data, error } = await (supabase as any).rpc('record_triage_assessment', payload);
  if (error) throw error;

  const id = String(data || crypto.randomUUID());
  return { id, patientId, row: { id, patient_id: patientId, ...payload } };
}
