export type TriageParameter = 'all' | 'temp' | 'bp' | 'bmi' | 'spo2';

export interface TriageHistoryRecord {
  id: string;
  patient_id: string;
  recorded_at: string;
  temperature: number | null;
  systolic: number | null;
  diastolic: number | null;
  bmi: number | null;
  oxygen_saturation: number | null;
}

export interface AxisConfig {
  domain: [number, number];
  ticks: number[];
  step: number;
}

const STEPS: Record<Exclude<TriageParameter, 'all'>, number> = {
  temp: 0.5,
  bp: 10,
  bmi: 2,
  spo2: 2,
};

export function normalizePatientId(patientId: string | null | undefined): string | null {
  const value = patientId?.trim();
  return value ? value : null;
}

export function selectTriageParameter(records: TriageHistoryRecord[], parameter: TriageParameter): TriageHistoryRecord[] {
  if (parameter === 'all') return records;
  return records.filter((record) => {
    if (parameter === 'temp') return record.temperature !== null;
    if (parameter === 'bp') return record.systolic !== null || record.diastolic !== null;
    if (parameter === 'bmi') return record.bmi !== null;
    return record.oxygen_saturation !== null;
  });
}

function floorToStep(value: number, step: number) {
  return Math.floor(value / step) * step;
}

function ceilToStep(value: number, step: number) {
  return Math.ceil(value / step) * step;
}

export function computeAxisConfig(values: number[], parameter: Exclude<TriageParameter, 'all'>): AxisConfig {
  const step = STEPS[parameter];
  const finite = values.filter(Number.isFinite);
  if (!finite.length) return { domain: [0, step], ticks: [0, step], step };

  let min = floorToStep(Math.min(...finite), step);
  let max = ceilToStep(Math.max(...finite), step);
  if (min === max) {
    min -= step * 2;
    max += step * 2;
  } else {
    min -= step;
    max += step;
  }

  const ticks: number[] = [];
  for (let tick = min; tick <= max + step / 10 && ticks.length < 20; tick += step) {
    ticks.push(Number(tick.toFixed(2)));
  }
  return { domain: [min, max], ticks, step };
}

export function formatTriageTime(value: number, rangeMs: number): string {
  const date = new Date(value);
  if (rangeMs <= 48 * 60 * 60 * 1000) {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }
  return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

export function isLowSpo2(value: number | null): boolean {
  return value !== null && value < 90;
}
