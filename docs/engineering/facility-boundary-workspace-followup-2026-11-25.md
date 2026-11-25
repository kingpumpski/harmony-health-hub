# Facility-boundary follow-up: maternity, pharmacy, operational and diagnostic workspaces — 2026-11-25

## Scope

Read-only review of hosted SECURITY DEFINER workspace RPC definitions in canonical
project `ygqoptvezotdqhtimdkr`, with source callsite checks against the repository.
No clinical or financial row contents were read. No production schema or data was
changed.

## Confirmed current findings

### Maternity workspace

`public.get_maternity_workspace(integer,uuid)` is SECURITY DEFINER with an empty
search_path and authenticated-only execution. It checks the caller's role and
episode-to-patient existence, but it does not resolve the caller's active facility
or constrain episodes/observations to that facility. Its episode-id check can
therefore confirm the existence of a foreign-facility episode before returning
data. The observation query inherits the same gap through episode-to-patient join.

Required repair: resolve active facility once; fail closed for ordinary clinical
staff if no active facility; enforce episode.patient facility equals active facility
for both list and selected-episode paths; return a non-disclosing not-found result
for foreign episodes; retain explicit, narrowly defined platform access; preserve
the RPC signature, JSON keys, limit behavior, role checks, and empty search_path.
The application calls this RPC from `src/pages/Maternity.tsx` for both episode
listing and observation loading.

### Department queue

`public.get_department_queue(text,integer)` is SECURITY DEFINER with an empty
search_path and detailed role/department checks. Its final query joins queue to
service order to patient but applies no facility predicate to any of the three.
The UI supplies only department and limit, so facility context must be resolved
inside the database function.

Previously inspected aggregate lineage showed seven active queue rows, all with
NULL queue facility; thirteen of fourteen service orders also have NULL facility.
All seven queue/order/patient chains have missing facility lineage, while their
patients have a facility. Consequently, filtering to active facility now would
hide all seven rows. Do not backfill from current patient facility without
authoritative evidence of the originating facility at transaction time. Preserve
the rows, reconcile via source workflow/audit lineage, quarantine ambiguous
records, and only then enforce a strict queue/order/patient facility match.

### Pharmacy workspace

`public.get_pharmacy_workspace(integer)` is SECURITY DEFINER with an empty
search_path. It includes a facility filter for patient, prescription and dispensing
plan results, but its `v_admin OR (... active facility ...)` predicates allow a
facility admin to bypass the facility check. This is not limited to the
non-identifying global medication catalogue. Patient-identifying prescription and
dispensing-plan data is exposed by the bypass.

Required repair: distinguish facility administrator from approved platform
operator; require non-null active facility and exact facility match for ordinary
admins and pharmacists; reserve global patient/claim access for explicitly
authorized platform roles; keep global catalogue semantics separate from
patient-specific work. Preserve expiry filters, JSON response keys and existing
role/department checks.

### Laboratory and imaging workspaces

`get_laboratory_workspace(integer)` and `get_imaging_workspace(integer)` are
SECURITY DEFINER with empty search_path and appropriate module role checks, but
their patient, order, and result queries do not constrain records to the caller's
active facility. Their RLS policies do not protect queries executed inside these
SECURITY DEFINER functions.

Required repair: resolve active facility; fail closed for ordinary staff without
one; scope patients and all linked orders/results by patient facility and
record-level facility where present; ensure no orphaned or cross-facility
order/result can enter the workspace; preserve the existing response shape and
department authorization.

### Canteen workspace

`get_canteen_active_patient_orders()` is SECURITY DEFINER with an empty
search_path and role checks, but its active meal-order query has no facility
predicate for the order or patient. It also returns patient names, dietary
restrictions, chronic-condition context and current diagnoses. Scope order and
patient to the active facility, and verify meal-plan lineage where facility-specific
plans exist. If menus/plans are intentionally global, retain that global catalogue
model but do not use it to widen patient/order access.

### Operational workspace

`get_operational_workspace(text,integer)` has a confirmed appointment branch
defect: an ordinary caller with NULL active facility passes the
`v_facility IS NULL` branch. Ward and bed branches also include NULL-facility
rows for every caller. The function currently treats `admin`, `it_admin`, and
`system_superuser` as one global bypass category. The correct platform-vs-facility
administrator distinction must be explicit before changing that behavior.

Required repair: require an active facility for ordinary staff; filter appointments
by patient facility and selected facility; do not include unassigned ward/bed rows
for ordinary staff; define global visibility only for a platform role explicitly
authorized by the product's role model. Preserve module-specific clinical roles
and empty search_path.

## Regression gates

Add database regression tests for:
- no active facility: ordinary workspace callers fail closed;
- same-facility records are returned;
- cross-facility records are excluded;
- foreign selected maternity episode is non-disclosing;
- department queue lineage requires queue, service order and patient facility
  consistency after data reconciliation;
- facility admins cannot use the platform/global bypass;
- platform exceptions are explicit and role-tested;
- JSON response keys, order, and limits remain backward compatible.

## Regression contract added

Added `supabase/tests/database/facility_boundary_workspace_contract.sql` with eight pgTAP checks covering maternity, department queue, pharmacy, laboratory, imaging, canteen, operational workspace and patient-audit facility boundaries. These checks are expected to fail against the currently inspected hosted definitions until the forward repairs are implemented. The contract has not yet been added to an automated disposable-database replay job.

## Deployment boundary

These are confirmed live-definition findings, not applied repairs. No forward
migration was generated because the environment still lacks a usable local
Supabase CLI and disposable PostgreSQL 17/Supabase replay target. Do not deploy
function replacements or data backfills until those verification prerequisites
are available. Existing PR #444 remains draft and unmerged.

## Follow-up verification gates — 2026-11-25

The migration workflow now explicitly runs the database regression contracts for:
- facility-boundary workspace reads;
- patient-audit access;
- billing-window special-form qualification; and
- `ensure_updated_at()` search-path pinning.

These checks run in the workflow's `verify` and `apply` modes after the normal migration preflight. They are not evidence that the fixes have already been applied. The live definitions inspected on 2026-11-25 still contain the documented defects, so a verify run against the current hosted schema is expected to fail closed until the forward repairs are implemented and safely deployed.

A fresh trigger-dependency query confirms `public.ensure_updated_at()` is attached to exactly three public tables: `lab_orders`, `lab_test_group_items`, and `lab_test_groups`. This narrows the blast radius of the planned empty-search-path pin; it does not replace regression testing of all three update paths.

The security advisor snapshot still reports two RLS-enabled/no-policy informational findings on the laboratory panel tables, one mutable-search-path warning on `ensure_updated_at()`, 279 authenticated-callable SECURITY DEFINER functions, and disabled leaked-password protection. No table grants, policies, function definitions, Auth settings, clinical rows, or financial rows were changed in this follow-up.

## Additional privilege and linkage verification — 2026-11-25

A fresh read-only catalog check confirms the following live conditions:

- PostgreSQL default EXECUTE ACLs for functions created by both `postgres` and `supabase_admin` in `public` explicitly include `anon` and `authenticated`. The existing two-assertion database contract is therefore a genuine outstanding blocker, not a hypothetical guard.
- `lab_test_groups` and `lab_test_group_items` each still grant `SELECT`, `INSERT`, `UPDATE`, and `DELETE` to both `anon` and `authenticated`. Their RLS/no-policy posture currently denies ordinary row access, but the excessive table ACLs remain unnecessary exposure and must be revoked in a forward migration after confirming owner/service-role and RPC behavior.
- `report_submissions` grants authenticated `SELECT`, `INSERT`, and `UPDATE`; it grants no direct `DELETE`. This conflicts with the intended read-only direct table contract because the application mutation paths were previously traced to governed RPCs. Revoke direct INSERT/UPDATE and remove the matching direct-write policies only after a forward migration has passed callsite and RPC regression checks.
- `ward_beds` grants authenticated SELECT only; its restrictive validated `admission_id` foreign-key contract remains an independent integrity gate.

The Supabase migration workflow now invokes the four corresponding database contracts in `verify` and `apply` modes. These tests intentionally inspect the linked hosted database without mutating it. Until the forward migrations are applied, the default-function ACL, laboratory panel ACL, Reports Center direct-write, and any still-missing ward-bed FK checks may fail; that failure is the intended safety signal. No ACL, policy, foreign key, function, or application data was changed during this review.

## Facility-boundary contract precision update — 2026-11-25

The eight-assertion facility contract has been tightened to normalize SQL whitespace and check the actual record lineage, rather than merely searching for a generic `facility_id` token. It now requires:
- maternity episode and patient facility equality, plus a fail-closed missing-facility branch;
- department queue, service order, and patient facility equality;
- pharmacy's platform-level exception to be distinct from facility-admin access, with the previous admin bypass predicates rejected;
- laboratory patient, order, and result facility predicates;
- imaging patient and imaging-order facility predicates;
- canteen order, patient, and meal-plan facility predicates;
- operational workspace rejection of null-facility bypasses and unassigned ward/bed rows; and
- patient-audit SELECT policy lineage through patient and active-facility authorization.

This stricter contract is expected to fail against the currently inspected hosted definitions: the maternity, department queue, laboratory, imaging, and canteen RPCs do not resolve active facility scope; the pharmacy RPC still grants facility-admin bypass on patient and dispensing-plan reads; the operational appointments branch contains a null-facility bypass and ward/bed branches include unassigned rows; and the patient-audit policy lacks facility lineage. The contract is a regression gate, not a repair. No hosted function or policy was altered.

## Nursing handover ward-link restoration — 2026-11-25

A read-only canonical catalog check confirms the deployed
`public.create_nursing_shift_handover(uuid,text,text,text,text,boolean,uuid)`
function inserts into `nursing_shift_handovers.ward_id`, while the live table
does not contain that column. The function already validates a supplied ward
against `ward_units.id` and the patient's resolved facility, and it uses an
empty search_path. The live handover table currently has zero rows, and the
proposed forward migration version `20261125090000` is not present in the
hosted migration ledger.

The existing forward migration restores a nullable UUID column, a
`ward_units(id)` foreign key with `ON DELETE SET NULL`, and a supporting
index. This preserves handover history if a ward is removed and does not
rewrite the deployed RPC. Added
`supabase/tests/database/nursing_handover_ward_link_contract.sql` with four
catalog assertions for column nullability/type, validated FK target, delete
behavior, and index validity. Registered it in the Supabase migration
workflow's `verify` and `apply` modes.

The migration and regression test are repository changes only. The SQL test
has not been executed because this environment has no local Supabase CLI or
disposable PostgreSQL 17/Supabase target; the hosted database has not been
changed. The migration workflow's normal historical-inventory preflight still
blocks a safe apply while the 21 duplicate historical migration-version
groups remain unresolved. Keep the PR draft and do not bypass that gate.

## Nursing handover migration conflict-detection hardening — 2026-11-25

The staged `20261125090000_restore_nursing_handover_ward_link.sql` migration
has been tightened before deployment. Previously, its idempotency checks
accepted any same-name foreign key or index without verifying that the existing
object actually represented the intended ward relationship. It now validates
the exact FK target, source/target columns, validation state, and
`ON DELETE SET NULL` behavior. It also validates that the named index is valid,
ready, and indexes only `ward_id`. A same-name conflicting object raises an
exception rather than being silently treated as success or automatically
dropped.

The Node static migration contract now checks these fail-closed conflict
branches and the database regression asset. This protects against an
environment where a prior partial/manual schema change created an object with
the expected name but incorrect definition.

These are source-level safeguards only. The static contract has not been run
in this environment, and the SQL migration and pgTAP test have not been
executed against PostgreSQL. The hosted schema and migration ledger remain
unchanged. The known migration-inventory blockers still prevent clean replay
and deployment.

## Operational workspace role-resolution defect — 2026-11-25

A fresh read-only inspection of the canonical
`public.get_operational_workspace(text,integer)` definition exposed a separate
authorization/availability defect. Its initial `v_role` resolution CASE handles
`system_superuser`, `admin`, `it_admin`, `practitioner`, `nurse`,
`midwife`, and `specialist_nurse`, then raises `Staff profile required`
when no role is resolved. Later module authorization branches explicitly list
`front_desk`, `accountant`, and `radiologist` for appointments, insurance,
facilities, and AI clinical workspaces, but those roles are not assigned to
`v_role` by the resolver. Those branches are therefore unreachable for users
whose relevant role is one of those three and who have no other role in the
resolver CASE.

The same live function confirms the facility-boundary issues recorded above:
the appointments predicate includes a role-independent
`v_facility IS NULL` bypass; ward and bed queries include
`facility_id IS NULL` rows for ordinary callers. The helper
`current_user_facility_id()` already distinguishes the system-superuser
selected-facility path from ordinary active-facility/membership resolution.
The intended platform-wide exception must therefore be expressed as an explicit
platform-role plus no-selected-facility condition, never as a standalone
null-facility bypass.

Expanded `facility_boundary_workspace_contract.sql` from eight to nine
assertions. The new assertion verifies that the three roles named by the
workspace's module authorization branches are actually mapped by its role
resolver. This is a regression gate and is expected to fail against the
currently inspected live definition. No function replacement or role grant was
made. A forward repair must preserve existing module-specific authorization,
add the missing resolver cases only after confirming their canonical enum
membership and app role semantics, and correct the appointment/ward/bed
facility predicates without granting facility administrators global access.
