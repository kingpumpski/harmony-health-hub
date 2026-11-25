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
