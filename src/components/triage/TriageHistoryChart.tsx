import { useMemo } from 'react';
import {
  Area,
  CartesianGrid,
  Line,
  LineChart,
  ReferenceArea,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import {
  computeAxisConfig,
  formatTriageTime,
  isLowSpo2,
  type TriageHistoryRecord,
  type TriageParameter,
} from '@/lib/triagePresentation';
import { useClinicalReferences } from '@/lib/clinicalReferences';

type Props = {
  records: TriageHistoryRecord[];
  parameter: TriageParameter;
};

const chartData = (records: TriageHistoryRecord[]) =>
  [...records]
    .sort((a, b) => new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime())
    .map((record) => ({ ...record, time: new Date(record.recorded_at).getTime() }));

function ParameterYAxis({ parameter, axisId, values }: { parameter: Exclude<TriageParameter, 'all'>; axisId: string; values: number[] }) {
  const config = computeAxisConfig(values, parameter);
  return <YAxis yAxisId={axisId} domain={config.domain} ticks={config.ticks} allowDecimals={parameter !== 'bp'} width={52} tick={{ fontSize: 11 }} />;
}

export default function TriageHistoryChart({ records, parameter }: Props) {
  const data = useMemo(() => chartData(records), [records]);
  const range = data.length > 1 ? data[data.length - 1].time - data[0].time : 0;
  const xFormatter = (value: number) => formatTriageTime(value, range);

  const tempValues = data.flatMap((r) => r.temperature === null ? [] : [r.temperature]);
  const bpValues = data.flatMap((r) => [r.systolic, r.diastolic].filter((v): v is number => v !== null));
  const bmiValues = data.flatMap((r) => r.bmi === null ? [] : [r.bmi]);
  const spo2Values = data.flatMap((r) => r.oxygen_saturation === null ? [] : [r.oxygen_saturation]);
  const { byParameter: referenceByParameter } = useClinicalReferences(['body_mass_index', 'spo2']);
  const bmiReference = referenceByParameter.get('body_mass_index');
  const spo2Reference = referenceByParameter.get('spo2');
  const bmiConfig = computeAxisConfig(bmiValues, 'bmi');
  const bmiUnderweightMax = Number(bmiReference?.thresholds?.underweight_max ?? bmiReference?.normal_min);
  const bmiOverweightMin = Number(bmiReference?.thresholds?.overweight_min ?? bmiReference?.normal_max);
  const bmiObesityMin = Number(bmiReference?.thresholds?.obesity_min ?? NaN);
  const spo2Threshold = Number(String(spo2Reference?.thresholds?.oxygen_therapy_threshold_percent ?? '').replace(/[^0-9.]/g, ''));

  const tempAxis = parameter === 'temp';
  const bpAxis = parameter === 'bp';
  const bmiAxis = parameter === 'bmi';
  const spo2Axis = parameter === 'spo2';

  if (!data.length) {
    return <div className="flex h-72 items-center justify-center rounded-xl border border-dashed p-6 text-center text-sm text-muted-foreground" role="status">No measurements are available for this parameter yet.</div>;
  }

  return (
    <div className="h-80 w-full" role="img" aria-label={parameter === 'all' ? 'Triage history chart showing temperature, blood pressure, BMI and oxygen saturation over time' : `Triage history chart for ${parameter}`}>
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 12, right: 18, left: 4, bottom: 12 }}>
          <CartesianGrid strokeDasharray="3 3" opacity={0.35} />
          <XAxis dataKey="time" type="number" domain={['dataMin', 'dataMax']} scale="time" tickFormatter={xFormatter} tick={{ fontSize: 11 }} minTickGap={28} tickCount={6} />
          {parameter === 'all' ? (
            <>
              <YAxis yAxisId="temp" orientation="left" hide />
              <YAxis yAxisId="bp" orientation="left" hide />
              <YAxis yAxisId="bmi" orientation="right" hide />
              <YAxis yAxisId="spo2" orientation="right" hide />
            </>
          ) : (
            <ParameterYAxis parameter={parameter} axisId={parameter} values={parameter === 'temp' ? tempValues : parameter === 'bp' ? bpValues : parameter === 'bmi' ? bmiValues : spo2Values} />
          )}

          {bmiAxis && Number.isFinite(bmiUnderweightMax) && Number.isFinite(bmiOverweightMin) && Number.isFinite(bmiObesityMin) && <><ReferenceArea yAxisId="bmi" y1={0} y2={bmiUnderweightMax} fill="currentColor" fillOpacity={0.04} /><ReferenceArea yAxisId="bmi" y1={bmiUnderweightMax} y2={bmiOverweightMin} fill="currentColor" fillOpacity={0.08} /><ReferenceArea yAxisId="bmi" y1={bmiOverweightMin} y2={bmiObesityMin} fill="currentColor" fillOpacity={0.05} /><ReferenceArea yAxisId="bmi" y1={bmiObesityMin} y2={bmiConfig.domain[1]} fill="currentColor" fillOpacity={0.04} /></>}
          {spo2Axis && Number.isFinite(spo2Threshold) && <ReferenceArea yAxisId="spo2" y1={0} y2={spo2Threshold} fill="currentColor" fillOpacity={0.08} />}
          {bpAxis && <><Area yAxisId="bp" type="monotone" dataKey="diastolic" stackId="bpBand" stroke="none" fill="transparent" fillOpacity={0} connectNulls /><Area yAxisId="bp" type="monotone" dataKey={(entry: any) => Math.max((entry.systolic ?? 0) - (entry.diastolic ?? 0), 0)} name="Pulse pressure" stackId="bpBand" stroke="none" fill="hsl(var(--primary))" fillOpacity={0.10} connectNulls /></>}
          
          {(parameter === 'all' || tempAxis) && <Line yAxisId="temp" type="monotone" dataKey="temperature" name="Temp" stroke="hsl(var(--warning))" strokeWidth={2.5} dot={false} connectNulls />}
          {(parameter === 'all' || bpAxis) && <>
            <Line yAxisId="bp" type="monotone" dataKey="systolic" name="Systolic" stroke="hsl(var(--destructive))" strokeWidth={2.5} dot={false} connectNulls />
            <Line yAxisId="bp" type="monotone" dataKey="diastolic" name="Diastolic" stroke="hsl(var(--primary))" strokeWidth={2.5} strokeDasharray="6 3" dot={false} connectNulls />
          </>}
          {(parameter === 'all' || bmiAxis) && <Line yAxisId="bmi" type="monotone" dataKey="bmi" name="BMI" stroke="hsl(var(--success))" strokeWidth={2.5} dot={false} connectNulls />}
          {(parameter === 'all' || spo2Axis) && <Line yAxisId="spo2" type="monotone" dataKey="oxygen_saturation" name="SpO₂" stroke="hsl(var(--info))" strokeWidth={2.5} dot={false} connectNulls />}
          {spo2Axis && Number.isFinite(spo2Threshold) && <ReferenceLine yAxisId="spo2" y={spo2Threshold} stroke="hsl(var(--destructive))" strokeDasharray="4 4" />}
          <Tooltip
            labelFormatter={(value) => new Date(Number(value)).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' })}
            formatter={(value: number, name: string) => [value, name]}
            contentStyle={{ borderRadius: 12 }}
          />
        </LineChart>
      </ResponsiveContainer>
      {(bmiAxis || spo2Axis) && (
        <div className="mt-2 text-xs text-muted-foreground">
          {bmiAxis && bmiReference && <>BMI reference bands: {bmiReference.display_text} Source: <a href={bmiReference.source_url} target="_blank" rel="noreferrer" className="underline">{bmiReference.source_name}</a>.</>}
          {spo2Axis && spo2Reference && <>SpO₂ threshold band: {spo2Reference.display_text} Source: <a href={spo2Reference.source_url} target="_blank" rel="noreferrer" className="underline">{spo2Reference.source_name}</a>.</>}
        </div>
      )}
    </div>
  );
}
