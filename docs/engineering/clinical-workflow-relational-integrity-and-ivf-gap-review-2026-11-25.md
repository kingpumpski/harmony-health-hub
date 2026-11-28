# Clinical workflow, relational integrity and IVF scope review — 2026-11-25

## Scope and safety

This is a software/database architecture review of the canonical Supabase project `ygqoptvezotdqhtimdkr` and application branch `chore/forward-only-migration-governance`. All database inspection was read-only. No canonical DDL, data, permissions, functions, or migration ledger entries were changed.

Clinical protocols, treatment decisions, stimulation regimens, embryo grading, and transfer decisions are deliberately outside this software audit. Those must be configured and approved by appropriately qualified clinical and laboratory governance teams.

## 1. Offline radiology route defect

The application routes both `/imaging` and `/radiology` to the Imaging workspace. The service worker previously returned an unhelpful synthetic 503 when a deep-link navigation received a hosting 5xx or a network failure and the app shell was not available through the network path. The root and index shell paths were also excluded from the navigation fallback path.

Forward fix committed:
- Bumped service-worker cache from `harmony-health-hub-shell-v17` to `v18`.
- Deep-link navigations now fall back to the network SPA shell for 404 and 5xx responses, then to the cached shell.
- Root/index navigations now use the same offline-capable navigation path.
- Removed generic same-origin GET caching. Only the application shell and fingerprinted build assets are cached; arbitrary responses are not cached, reducing the risk of stale operational or clinical payloads being retained by the service worker.
- Added `scripts/service-worker-navigation-offline-contract.mjs`, registered in the Quality workflow. It exercises 503-to-shell recovery and network-offline cached-shell recovery.

This improves navigation resilience. It does not make live radiology orders, image retrieval, reporting, or clinical writes available without a server connection. The worklist must show a clear offline state and must never imply that a remote clinical action succeeded when it did not.

## 2. Cross-module relational integrity

The canonical database has 156 public tables, 156 with RLS enabled, 681 indexes, 389 foreign keys, and 192 check constraints.

A generated-type relationship comparison identified four expected clinical/operational links missing from the current catalog:

| Child table | Column | Expected parent | Read-only orphan check |
|---|---|---|---:|
| `emergency_cases` | `patient_id` | `patients.id` | 0 |
| `transfusion_records` | `patient_id` | `patients.id` | 0 |
| `medication_administrations` | `prescription_id` | `prescriptions.id` | 0 |
| `ward_beds` | `admission_id` | `admissions.id` | Not included in the orphan-count query |

The first three orphan checks returned zero at inspection time. This is useful preflight evidence, not approval to add constraints. The FK delete action must be selected to preserve clinical record retention and historical traceability. In particular, medication-administration history must not disappear merely because a prescription record is removed.

Added:
- `scripts/module-relationship-contract.mjs`
- `scripts/module-relationship-exceptions.json`
- `test:module-relationship-contract` in the Quality workflow

The contract verifies expected cross-module relationships from the generated canonical schema and requires every missing relationship to have an explicit, reviewable exception. Once a forward migration is validated and generated types show the FK, its exception must be removed.

## 3. Patient-record retention risk

The canonical catalog currently has `ON DELETE CASCADE` patient relationships for appointments, encounters, admissions and fertility cycles; fertility monitoring also cascades from its cycle. This is a material retention risk if a patient row can be physically deleted.

Required safeguard:
- Treat patient identity as a durable master record.
- Use a reviewed inactive/merged/deceased/archived state model rather than routine physical deletion.
- Restrict hard deletion of records with clinical, billing, diagnostic, fertility or audit history.
- Before changing existing FK delete actions, inspect every dependent table and all deletion RPCs; do not apply a blanket RESTRICT migration without a dependency/retention plan.
- Add regression tests proving patient archival preserves clinical history.

## 4. Appointment → encounter → admission → discharge review

### Verified positive controls

- Appointment creation checks authenticated role, active facility, active patient and patient/facility match.
- Starting an appointment encounter checks clinician role, appointment ownership/facility context and idempotently reuses the latest encounter for that appointment.
- Admission creation checks patient activity and facility, requires an active ward in the same facility, uses an advisory lock to prevent duplicate active admissions, and validates bed/ward/facility alignment.
- Bed transfer checks active admission and facility, locks relevant rows, validates source/target beds, updates occupancy and records a care-transition event.
- Discharge checks role and patient facility context, locks the admission, validates bed ownership, marks the admission discharged, moves the bed to cleaning, emits a billing handoff notification and records an audit event.

### Gaps to close before calling this a complete digital-care pathway

1. The appointment creation function verifies the selected clinician exists but its inspected body does not enforce a clinician availability/overlap rule. Add transactional conflict detection and a database-level concurrency strategy, not only a UI check.
2. The admission UI currently submits a generic discharge summary. The inspected discharge RPC handles admission state, bed release, billing handoff and audit, but does not enforce a structured discharge-readiness checklist, medication reconciliation, follow-up ownership, patient instructions, pending-result handoff or a completed care-transition record.
3. `ward_beds.admission_id` currently has no FK in the inspected catalog. This must be reconciled with historical occupancy and bed-movement records.
4. Physical deletion cascades need a durable clinical-record retention policy.
5. Appointment cancellation, no-show, rescheduling, waiting-list promotion, referral conversion and rebooking need explicit allowed state transitions, actor attribution, timestamps and idempotency tests.
6. Admission, bed allocation, discharge and billing need cross-module integration tests for retries, concurrent users, facility boundaries, partial failures and duplicate requests.

## 5. IVF/Fertility scope and security review

### What exists today

The canonical database currently exposes only two fertility-specific tables:
- `fertility_cycles`
- `fertility_monitoring`

The current Fertility page supports cycle creation for IVF/IUI/ICSI/FET, a limited set of monitoring measurements, and a simple cycle status/outcome transition. The database exposes three principal RPC workflows:
- `create_fertility_cycle_workflow`
- `record_fertility_monitoring_workflow`
- `transition_fertility_cycle_workflow`

RLS is enabled on both tables. The inspected policies provide SELECT access; direct authenticated INSERT/UPDATE/DELETE is revoked and writes are routed through SECURITY DEFINER RPCs.

### Critical security issue

The live `transition_fertility_cycle_workflow` SECURITY DEFINER function checks authentication and a broad clinical role, then updates the cycle by ID. Its current body does **not** assert patient facility context or compare the cycle's facility with the caller's active facility. Because SECURITY DEFINER functions execute with their owner's privileges, RLS alone is not a sufficient boundary.

This requires a forward-only function repair with:
- cycle row lock and patient/facility lookup;
- patient-facility assertion;
- active facility equality for non-privileged staff;
- explicit, documented privileged-role rules;
- allowed transition graph and terminal-state rules;
- actor, timestamp, facility and before/after audit details;
- tests for same-facility success, cross-facility denial, missing facility, unauthorized role, invalid transition, repeated request and concurrent transition.

The live `create_fertility_cycle_workflow` body also lacks the advisory lock found in an earlier source candidate's cycle-number allocation logic. The live function should be reconciled against the exact deployed source and concurrency-tested before relying on `MAX(cycle_number)+1` under simultaneous requests.

### IVF domain model gap

The present two-table model is not a complete IVF/embryology operational system. A properly governed next design should separately model and link (without prescribing clinical treatment):
- consent and authorization records, including version, scope, signatory, witness and expiry/revocation state;
- cycle episode and planned/actual milestone events;
- laboratory orders and specimen accession for gamete/material collection;
- specimen identity, labels, custody events, location, hand-offs and dual-witness verification;
- embryology laboratory work records and fertilization/culture event history;
- embryo inventory/identity, status, observations and traceable disposition;
- cryostorage inventory, tank/cane/goblet location, movement, alarm and reconciliation events;
- transfer procedure records and linked clinical encounter;
- outcome/follow-up records and adverse-event/incident reporting;
- billing/service-order links and audit trails.

Every reproductive-material and embryo record requires immutable identity, parent/episode linkage, facility isolation, actor/time provenance, custody history, correction/amendment history and explicit authorization. Do not treat free-text notes as a substitute for structured chain-of-custody records.

The detailed domain design must be reviewed by clinical leadership, embryology/laboratory leadership, privacy/security, legal/compliance and the applicable regulator before schema implementation. Clinical decision support must remain advisory, explainable, versioned, validated and clinician-controlled.

## 6. Duplicate migration identities — resolution strategy

The 21 duplicate 14-digit version groups must not be resolved by choosing an arbitrary file, renaming one to a later timestamp, deleting one, or disabling the validator. The fact that the 21 prefixes are absent from the captured 417-row hosted ledger does not prove their SQL was never executed in another environment or manually.

Recommended controlled resolution:

1. Freeze the original migration files and record SHA-256, Git provenance, source branch, object/signature inventory and dependency references for both/all candidates in each collision group.
2. Recover the exact pre-Supabase development baseline and missing canonical baseline SQL where possible. Preserve evidence from deployment bundles, old Git clones, CI artifacts and backups.
3. For each collision group, compare every candidate against the authoritative live catalog and all later hosted migrations: tables/columns, constraints, indexes, functions and overloads, policies, grants, triggers, default privileges, dependencies and behavior.
4. Classify each candidate as already represented, still required, superseded, incompatible, or unresolved. Require evidence and reviewer sign-off for every classification.
5. Keep the existing hosted ledger unchanged. Create a separately documented clean-install bootstrap from a complete reviewed schema snapshot if exact historic replay cannot be reconstructed. Do not mislabel a current schema dump as the missing September 2026 baseline.
6. Keep clean-install bootstrap and existing-hosted-database upgrade paths distinct. The existing project continues from its actual hosted ledger; a new empty project uses the approved bootstrap and only subsequent forward migrations.
7. Replay the approved path on disposable PostgreSQL 17/Supabase, then compare catalog, functions, privileges, RLS, policies, extensions, triggers and workflow tests with the authoritative snapshot.
8. Only after the above passes should the active migration inventory and CI gate be changed. Preserve an archive of original collision files and a signed reconciliation manifest.

The migration contract currently validates identities before starting the clean database service. This is correct fail-fast behavior; it prevents a misleading replay result.

## 7. Release gates

Do not call a workflow production-ready until its:
- table/column/nullability/default contract;
- FK and delete-action contract;
- indexes and uniqueness/concurrency contract;
- RLS and function privilege contract;
- RPC signature/return/error contract;
- state-transition and idempotency contract;
- audit and retention contract;
- facility isolation contract;
- end-to-end workflow contract;
- clean migration replay and schema parity

have passed.

The current PR remains draft and unmerged. The proposed radiology offline fix and new contracts are repository changes only; no canonical production database migration was applied.
