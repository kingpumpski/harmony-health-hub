# Patient audit privacy and facility-boundary repair — 2026-11-27

## Read-only live findings

Project `ygqoptvezotdqhtimdkr` was inspected read-only.

- `patient_audit_log` has RLS enabled but an effective SELECT policy that allows any clinical staff member or admin without checking the active facility or patient-to-facility lineage.
- The Patient Hub audit page reads `patient_audit_log` and currently selects only `id, action, changed_at, changed_by, changed_fields`. No current app reader of the legacy `patient_audit` table was found.
- Both `patient_audit_log` and `patient_audit` have broad anon/authenticated table ACLs, including direct mutation privileges. RLS limits some operations, but the direct grants are broader than the application needs.
- The two patient row triggers write full OLD/NEW patient snapshots into JSONB columns. The UI no longer reads those values, so retaining full row snapshots for new audit events is unnecessary for the current audit display.
- The legacy `patient_audit.patient_id` foreign key is `ON DELETE RESTRICT` and the column is NOT NULL. Because its DELETE audit trigger inserts a row before the patient is deleted, that FK can block patient deletion. The parallel `patient_audit_log` FK already uses `ON DELETE SET NULL`.
- The trigger functions are SECURITY DEFINER. Their search paths were previously pinned to `pg_catalog, public`; the staged replacement pins them to an empty path and schema-qualifies referenced objects.

## Forward-only repair staged

Migration: `supabase/migrations/20261127104000_harden_patient_audit_privacy_and_facility_access.sql`

- Revokes PUBLIC, anon and authenticated direct table privileges from both audit tables.
- Re-grants authenticated SELECT only on `patient_audit_log`, the current UI read surface.
- Leaves `patient_audit` inaccessible directly to client roles; trigger-owned inserts remain available.
- Replaces the broad audit-log SELECT policy with a policy requiring an existing patient row in the caller's active facility and clinical-staff/admin role.
- Replaces both SECURITY DEFINER patient audit trigger functions with empty search paths.
- Changes the legacy audit table patient FK to nullable `ON DELETE SET NULL`, preserving the deletion audit event instead of blocking patient deletion.
- Preserves audit action, actor, timestamp, patient ID and changed-field names, but writes NULL to future `old_record`/`new_record` values. Existing historical audit rows are not rewritten or deleted.
- Revokes direct EXECUTE on the trigger functions from PUBLIC, anon and authenticated.

## Regression coverage

Updated `supabase/tests/database/patient_audit_access_contract.sql` to assert:
1. RLS remains enabled on both audit tables.
2. Anonymous clients have no direct table privileges.
3. Authenticated clients can SELECT only the facility-scoped audit log and cannot read the legacy snapshot table or mutate either table.
4. The audit-log SELECT policy checks active facility and patient lineage.
5. No broad clinical-staff-only policy remains.
6. Orphan audit rows are not exposed by a read policy.
7. Trigger functions remain SECURITY DEFINER, empty-search-path and not client-callable.
8. Future trigger events retain changed-field names without storing old/new row snapshots.
9. Patient deletion preserves the audit event through a nullable `ON DELETE SET NULL` relationship.

The Patient Hub UI continues to use the changed-field-only projection.

## Limits and release status

This is a staged repository migration only. It has not been applied to the hosted database. Existing historical old/new snapshots remain unchanged pending an explicit retention/compliance decision; this migration does not rewrite or delete historical audit evidence. The duplicate migration/source-history blocker still prevents disposable PostgreSQL replay, so runtime database validation remains pending. No live data, schema, Auth, Storage or project settings were changed.


## CI checkpoint

On commit `0ac70450934e0d9713df67ef14b273b51f19e45a`:
- Quality workflow [#46025174154](https://github.com/kingpumpski/harmony-health-hub/actions/runs/46025174154) passed.
- Migration contract workflow [#46025174160](https://github.com/kingpumpski/harmony-health-hub/actions/runs/46025174160) passed the migration-parity source contracts, including the nine-assertion patient audit source contract, then failed closed at the 21 duplicate migration-version preflight. PostgreSQL startup and SQL replay were skipped.
- The database contract itself has not executed against PostgreSQL yet. The staged migration remains unapplied.
