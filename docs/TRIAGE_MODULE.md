# Triage module redesign

## Scope

This change keeps the existing triage persistence and clinical workflow intact while separating the operational landing list from the patient-scoped longitudinal view.

### Files changed

- `src/pages/Triage.tsx` — patient triage landing list, loading/error/empty states, and Add Record flow.
- `src/components/triage/TriageRecordForm.tsx` — reusable guided entry form with inline validation and field placeholders.
- `src/components/triage/TriageHistoryChart.tsx` — Recharts longitudinal visualization with parameter-specific rendering.
- `src/lib/triagePresentation.ts` — patient-ID guard, client-side parameter filtering, time formatting, and per-parameter axis intervals.
- `src/pages/patients/PatientHub.tsx` — replaces the previous raw vitals table with a strictly patient-scoped triage history, graph, filters, and Add Record flow.
- `src/pages/patients/PatientSearch.tsx` — adds the patient-specific View Vitals entry point.
- `supabase/migrations/20260928145648_patient_scoped_triage_history.sql` — adds the server-side `get_patient_triage_history` RPC.
- `scripts/triage-contract.mjs` — regression contracts for scoping, filters, chart behavior, states, validation and placeholders.
- `package.json` — wires the triage contract into the existing test command.

## Axis choices

- Temp: 0.5 °C ticks.
- BP: 10 mmHg ticks; systolic and diastolic are always rendered together when BP is selected, with a pulse-pressure band between them.
- BMI: 2 kg/m² ticks plus faint underweight/normal/overweight/obesity reference zones.
- SpO₂: 2% ticks plus a highlighted <90% threshold band.
- X-axis uses timestamps and adapts its labels between time-of-day and calendar-date presentation according to the visible time span, with a minimum tick gap to reduce overlap.

## End-user presentation

Internal IDs, recorded-by UUIDs, update timestamps and verbose audit/debug metadata are not shown in the triage summary. The underlying records remain available to the application's existing audit/security workflows. Clinical notes are optional and hidden from the graphical/list summary.

The entry form uses placeholders that show expected units/examples and allows partial measurements because the production triage schema supports nullable measurements. At least one measured vital sign is required.

## Data boundary

The Patient Hub does not query a global triage list. It calls `get_patient_triage_history(_patient_id)`, which has an explicit `patient_id = _patient_id` predicate and returns no rows when the patient ID is null. Parameter filters run only against the already-loaded patient dataset.
