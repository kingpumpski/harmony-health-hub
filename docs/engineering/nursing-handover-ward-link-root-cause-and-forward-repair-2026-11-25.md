# Nursing handover ward-link root-cause and forward repair — 2026-11-25

## Executive finding

The nursing-handover runtime failure is a schema/RPC drift, not a missing UI argument.

The canonical hosted database has:
- `public.nursing_shift_handovers` with no `ward_id` column.
- `public.ward_units.facility_id`.
- A deployed `public.create_nursing_shift_handover(..., _ward_id uuid DEFAULT NULL)` function that validates a supplied ward against the patient's facility and then inserts `ward_id`.
- Zero existing handover rows and no ward-related index on the handover table.

The deployed function fails at statement planning/execution because its INSERT target list names a column that the table does not contain. Omitting `_ward_id` from the UI does not avoid the failure: the function still names the column and passes NULL.

## Hosted migration chronology

The read-only Supabase migration listing confirms these hosted ledger identities:

| Hosted version | Hosted migration name | Relevance |
|---|---|---|
| `20260916002251` | `canonical_remote_schema` | Canonical baseline is recorded in the hosted ledger, but its original SQL source is absent from the repository and has not been recovered. |
| `20260918090246` | `operational_workspace_nursing_care_extension` | Later nursing workspace extension. |
| `20260921052442` | `20260920084000_referral_handover_lifecycle_consistency_hardening` | Defines a handover RPC that inserts `ward_id`. |
| `20261004193612` | `harden_care_transition_handover_lab_approval` | Replaces the handover RPC with facility-aware validation, but still inserts `ward_id`. |

The active repository contains the two historical function definitions above, both expecting `ward_id`. The original canonical baseline SQL is not available to prove which initial table definition was used or why the column was omitted. Therefore this report does **not** attribute the omission to one specific colliding September migration candidate.

The key chronology is established: the baseline is recorded, later hosted handover RPC migrations assume the ward column, and the current live table does not provide it. The precise migration at which the column was omitted cannot be proven without the original baseline SQL.

## Canonical live evidence

Read-only catalog inspection on project `ygqoptvezotdqhtimdkr` returned:

- `handover_has_ward_id = false`
- `handover_rows = 0`
- `ward_indexes = 0`
- `ward_units_has_facility_id = true`
- The live RPC signature includes optional `_ward_id uuid DEFAULT NULL`.
- The live RPC checks `public.ward_units` for both the requested ward ID and `facility_id = pf`.
- The live RPC INSERT column list includes `patient_id, facility_id, ward_id, ...`.

The UI continues to call the controlled RPC and omits the optional `_ward_id` argument. That is valid once the nullable table column is restored.

## Forward-only repair added to this PR

Added:

`supabase/migrations/20261125090000_restore_nursing_handover_ward_link.sql`

It:
1. Adds nullable `ward_id uuid` with `ADD COLUMN IF NOT EXISTS`.
2. Adds the foreign key to `public.ward_units(id)` with `ON DELETE SET NULL`, if the expected FK is not already present.
3. Adds a supporting index.
4. Documents the facility-scope rule.
5. Does not rewrite the deployed RPC, historical migrations, or existing handover data.

The canonical table currently has zero rows, so the new nullable column requires no backfill for the inspected environment. The RPC remains responsible for checking that a supplied ward belongs to the same facility as the patient. Existing RLS and restricted direct-write boundaries remain unchanged.

This is an additive migration proposal committed to the draft PR only. It has **not** been applied to the canonical database.

## Regression contract

Added `scripts/nursing-handover-schema-contract.mjs`, registered it in the package test chain, and added it as a dedicated Quality workflow step. The contract checks:
- The migration version sorts after the verified hosted ledger latest version.
- The nullable column, FK delete behavior, and supporting index are present.
- The migration contains no destructive table/column/index operations and does not replace the RPC.
- The existing facility-aware RPC source checks same-facility ward ownership and persists the ward link.
- The UI continues to use the RPC and may omit the optional ward argument.

This is a source/contract regression test, not a substitute for executing the migration against PostgreSQL.

## Validation still required before deployment

- Run the migration and handover RPC against a disposable PostgreSQL 17/Supabase database.
- Verify the FK, index, RLS policies, grants, and same-facility rejection behavior.
- Exercise both the no-ward UI path and a valid same-facility ward path.
- Verify cross-facility ward selection is rejected.
- Re-run the full migration replay and catalog parity checks.

No local PostgreSQL server, `psql`, Docker, or Podman runtime was available in this engineering session. No paid Supabase branch was created. Do not apply this migration to canonical production until disposable replay and the remaining migration provenance gates pass.

## Safety disposition

Canonical Supabase inspection remained read-only. No live schema, data, function, grant, policy, trigger, or deployment was changed. PR #444 remains draft and unmerged.
