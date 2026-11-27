# Acute clinical lifecycle facility isolation review — 2026-11-27

## Finding

The latest repository definitions of three SECURITY DEFINER lifecycle RPCs retained an administrator bypass that was broader than the intended facility boundary:

- `transition_emergency_case(uuid,text,text)` validated that the emergency case facility matched the patient facility, but did not require the caller's active facility to match. Its role gate also omitted `system_superuser`.
- `transition_theatre_case(uuid,text,text)` explicitly exempted `admin` and `it_admin` from the active-facility check, in addition to `system_superuser`.
- `record_transfusion_event(uuid,text,boolean,text)` exempted `admin` from active-facility matching and did not admit `system_superuser` through its role gate.

## Forward-only correction

`20261127100600_fix_acute_clinical_lifecycle_facility_scope.sql` performs guarded replacements against the exact existing function identities. It:

- Requires an active facility matching the patient's facility for emergency transitions, including facility administrators.
- Rejects emergency cases or patients without resolvable facility attribution.
- Makes facility administrators and IT administrators facility-scoped for theatre transitions.
- Makes facility administrators facility-scoped for transfusion events.
- Explicitly admits `system_superuser` to each RPC and reserves cross-facility bypass for that role only.
- Preserves the existing clinical lifecycle transition rules, patient/facility lineage checks, function signatures, SECURITY DEFINER mode, empty search_path, and authenticated EXECUTE grants.
- Aborts if any expected source anchor is missing or appears an unexpected number of times.

## Verification limits

The static contract verifies source anchors, exact RPC identities, active-facility predicates and ACL statements. It does not execute PostgreSQL or prove the hosted function definitions. No database was accessed or modified, no Supabase branch was created, and no migration was applied. The 21 duplicate historical migration-version groups remain the primary migration preflight blocker.
