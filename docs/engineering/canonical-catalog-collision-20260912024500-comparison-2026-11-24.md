# Canonical catalog comparison for the 20260912024500 collision — 2026-11-24

## Evidence and limits

This report compares the two same-version SQL candidates in the supplied project ZIP with read-only catalog observations from the controlled canonical Supabase project `ygqoptvezotdqhtimdkr`.

Source candidates:
- `20260912024500_global_hims_enterprise_operations.sql`
- `20260912024500_global_hims_inpatient_emergency_theatre_insurance.sql`

Live evidence queried:
- `information_schema.columns`: column order, names, types, nullability, and defaults for five public tables.
- `information_schema.table_constraints` joined to `pg_constraint`: primary keys, foreign keys, and check constraints.

The query did not alter the database. This comparison is not a complete table-definition dump: it does not fully inventory indexes, policies, triggers, grants, comments, partitioning, RLS flags, or function dependencies. The hosted catalog is a later evolved state, so matching a live column to one candidate is not proof that candidate was applied.

## Findings by table

### `public.emergency_cases`

- Candidate A (enterprise operations) defines `arrival_at`, non-null `arrival_mode` defaulting to `walk_in`, `triage_priority`, nullable `chief_complaint`, and `notes`; it has no patient FK in its initial table declaration.
- Candidate B (inpatient/emergency/theatre/insurance) defines `arrival_time`, nullable `arrival_mode`, `acuity`, non-null `chief_complaint`, `triage_summary`, and a patient FK with `ON DELETE SET NULL`.
- Canonical live table contains the Candidate A base fields `arrival_at`, `triage_priority`, `notes`, plus Candidate B's `arrival_time` and `acuity`, and later `facility_id`.
- Live constraints include Candidate A's arrival-mode and triage-priority checks and its status vocabulary; live patient_id remains nullable and has no patient FK. A facility FK is present.
- Interpretation: live is a hybrid/evolved shape, not a clean match to either initial CREATE TABLE. Choosing either candidate as the winner would discard known live fields or constraints.

### `public.nursing_care_plans`

- Candidate A defines nullable `interventions`, requires `created_by` with `ON DELETE RESTRICT`, and includes `reviewed_by`; it does not initially define `encounter_id`.
- Candidate B requires `interventions`, makes `created_by` nullable with `ON DELETE SET NULL`, adds `encounter_id` and `reviewed_at`, and declares a patient FK with `ON DELETE CASCADE`.
- Canonical live table has nullable `interventions`, non-null `created_by`, `encounter_id`, and `facility_id`; it does not have `reviewed_at`. Its live created_by FK is `ON DELETE RESTRICT`; there is no patient FK. The encounter FK uses `ON DELETE SET NULL`.
- Interpretation: live aligns with some Candidate A semantics and some later additions, but differs materially from Candidate B's nullability and referential actions. A blind replay of either original CREATE TABLE would be unsafe.

### `public.nursing_shift_handovers`

- Candidate A defines `admission_id`, `shift_date` defaulting to current date, `shift_name` defaulting to `general`, `outstanding_tasks`, and `risks_and_alerts`.
- Candidate B defines `ward_id`, `shift_label`, `pending_tasks`, and `safety_concerns`, with a patient FK using `ON DELETE CASCADE`.
- Canonical live table includes Candidate A's `admission_id`, `shift_date`, `shift_name`, `outstanding_tasks`, and `risks_and_alerts`, plus Candidate B's `shift_label`, `pending_tasks`, and `safety_concerns`, and later `facility_id`. It has no `ward_id`.
- Live patient FK is `ON DELETE RESTRICT`, not Candidate B's cascade behavior.
- Interpretation: live is an additive hybrid of both naming sets with a later facility scope. This is strong evidence that neither original CREATE TABLE alone describes the final canonical contract.

### `public.theatre_cases`

- Candidate A defines `theatre`, `anaesthetist_id`, optional `scheduled_at`, status values `planned/cleared/in_progress/completed/cancelled/postponed`, and `anaesthetic_cleared` / `consent_confirmed`.
- Candidate B defines `theatre_name`, `anesthetist_id`, required `scheduled_start`, optional `scheduled_end`, `urgency`, a different status vocabulary, and pre/post-operative fields.
- Canonical live table has `theatre` and `theatre_name`, both spellings `anaesthetist_id` and `anesthetist_id`, `scheduled_start`, `scheduled_at`, `urgency`, and later `encounter_id` / `facility_id`.
- Live constraints use Candidate A's status vocabulary and Candidate B's urgency vocabulary. Live `scheduled_start` is nullable, although Candidate B initially required it.
- Interpretation: canonical table is an additive compatibility shape with two spellings and two schedule columns. This requires application call-site and generated-type review before any consolidation or deprecation.

### `public.transfusion_records`

- Candidate A defines `component` with a constrained vocabulary, optional `unit_identifier`, `status` values including `verified` and `reaction`, and free-text `notes`.
- Candidate B defines required `blood_product` and `unit_identifier`, optional `volume_ml`, boolean `reaction_observed`, and a different status vocabulary.
- Canonical live table has `component`, `blood_product`, `unit_identifier`, `reaction_observed`, `reaction_notes`, and later `encounter_id` / `facility_id`. `unit_identifier` and `blood_product` are nullable. `volume_ml` is absent.
- Live check constraints use Candidate A's `component` and status vocabularies. Live has no check on `blood_product` in the queried constraint set.
- Interpretation: live combines parts of both candidate contracts, with Candidate A's checks and additional fields. It is not safe to infer that Candidate B's required fields or status semantics were adopted.

## Cross-cutting conclusion

All five live tables have later facility scoping columns and facility foreign keys. Several also have encounter links. The observed catalog contains additive compatibility fields from both colliding candidates, while retaining only one side's nullability, referential actions, or check constraints in important places.

This is a material reason not to rename, drop, or choose one of the same-version files. The hosted schema is an evolved state that cannot be reconstructed by picking a single initial DDL file.

## Required next work before migration repair

1. Export complete canonical DDL for these five tables, including indexes, policies, triggers, grants, RLS flags, and function references.
2. Search application source, generated Supabase types, RPC bodies, and edge functions for every column spelling and enum/check vocabulary above.
3. Recover the chronological migrations that added the hybrid fields and constraints; identify whether they came from later tracked migrations, manual dashboard edits, or other deployment sources.
4. Build a compatibility migration only after its desired final contract is agreed and its data-preservation behavior is reviewed.
5. Replay the recovered chain on disposable PostgreSQL 17 and compare catalog output, not merely successful migration exit status.

## Safety disposition

Read-only catalog inspection only. No SQL migration, table alteration, data mutation, policy change, grant change, or deployment was performed. The canonical project remains unchanged.
