# Operational workspace facility-isolation review — 2026-11-27

## Finding

The latest effective source definition was introduced by `20261013133000_reconcile_operational_workspace_role_resolution.sql`. Its `get_operational_workspace(text,integer)` branches contained several unsafe facility predicates:

- Appointment results allowed administrator roles to bypass patient facility matching and did not require the appointment's own facility to match.
- Ward and bed results included rows with NULL facility attribution for ordinary workspace users and facility administrators.
- Seven patient-linked branches treated a platform administrator with no active facility as a special case rather than requiring an explicit facility selection; facility administrators and IT administrators were not consistently separated from the global superuser role.

## Forward-only correction

`20261127100500_fix_operational_workspace_facility_scope.sql` retrieves the exact existing function definition and performs guarded, count-checked source replacements. It:

- Requires an active facility for non-superuser access to appointments, ward, nursing care, emergency, handover, theatre, transfusion, insurance, and medication-administration workspaces.
- Requires both appointment and patient facility IDs to match the active facility.
- Requires patient-linked workspace rows to belong to the active facility.
- Excludes unassigned legacy ward and bed rows from facility-scoped workspaces.
- Reserves cross-facility reads for `system_superuser`; `admin` and `it_admin` remain facility-scoped.
- Preserves the RPC identity, return type, module branches, SECURITY DEFINER mode, empty search_path, and authenticated-only EXECUTE grant.
- Fails migration execution if the deployed function definition does not match the expected replacement anchors and counts.

The facilities directory and data-migration branches retain their existing platform-control-plane behavior. The AI-clinical session table has an explicit facility_id added by the historical facility-attribution migration; the repair now scopes this branch to that facility and includes it in the active-facility requirement.

## Verification limits

The static contract verifies the reviewed source anchors, expected replacement counts, facility predicates, and RPC ACL. It does not execute PostgreSQL or prove deployed function behavior. No database was accessed or modified, no Supabase branch was created, and no migration was applied. The existing 21 duplicate historical migration-version groups still block migration preflight and clean replay.
