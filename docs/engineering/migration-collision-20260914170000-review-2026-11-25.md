# Migration collision review: 20260914170000

Updated: 2026-11-25

## Scope and decision

Compared both candidates sharing version `20260914170000` with canonical table privileges, RLS policies, function signatures, and execute grants:

- `20260914170000_clinical_insurance_case_direct_mutation_hardening.sql`
- `20260914170000_clinical_triage_medication_mutation_hardening.sql`

The canonical database already has authenticated direct DML revoked on insurance cases, triage assessments and medication administrations. The current RPC entry points exist and are authenticated-only. However, the triage candidate references a function signature that does not exist in the canonical catalog.

**Disposition:** retain both candidates. The first is substantially reflected in the live database. The second's table revocations are reflected, but its function privilege statements are not safe to replay as written.

## A. Insurance case direct-mutation hardening

Canonical inspection confirms:
- `insurance_cases` has RLS enabled.
- Authenticated INSERT/UPDATE/DELETE are revoked.
- The permissive clinical/accounts policy is constrained by restrictive facility SELECT policies.
- `update_insurance_case(uuid,text,text,text,numeric,numeric,text)` exists, is SECURITY DEFINER, has a pinned `pg_catalog, public` search path, and is executable by authenticated but not anon.

The live RPC's definition should remain the authoritative contract. The candidate's privilege change is already reflected in the canonical ACL; do not apply it again solely because it appears in a duplicate migration group.

## B. Triage and medication mutation hardening

Canonical inspection confirms:
- `triage_assessments` has RLS enabled and authenticated direct INSERT/UPDATE/DELETE revoked.
- `medication_administrations` has RLS enabled and authenticated direct INSERT/UPDATE/DELETE revoked.
- The current `record_triage_assessment` function is SECURITY DEFINER with an empty search path, executable by authenticated but not anon.
- `schedule_medication_administration`, `transition_medication_administration`, and `reopen_medication_administration` exist, are SECURITY DEFINER, have pinned search paths, and are executable by authenticated but not anon.

### Confirmed migration execution defect

The candidate attempts to revoke/grant:
`public.record_triage_assessment(UUID, INTEGER, INTEGER, INTEGER, NUMERIC, INTEGER, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT, BOOLEAN)`

The canonical catalog has only:
`public.record_triage_assessment(UUID, INTEGER, INTEGER, INTEGER, NUMERIC, INTEGER, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT, TEXT, TEXT)`

That is a 15-argument candidate signature versus a 14-argument live function. The referenced overload is absent. On a database with the inspected catalog, the candidate's function-level REVOKE/GRANT statements will fail with a missing-function error unless the overload is created earlier in the same migration chain. No such overload was found in the live catalog.

This is not a reason to invent the missing overload. Reconcile the original intended function contract, its callsites, and its source migration before any new migration is authored.

### RLS and workflow notes

The current triage policies include clinical-role INSERT with `recorded_by = auth.uid()`, admin UPDATE, and restrictive facility SELECT policies. Direct authenticated DML is currently blocked at the ACL layer, so the permissive INSERT/UPDATE policy definitions do not independently permit PostgREST writes without the required table privilege.

The medication administration table has a role-based permissive ALL policy plus restrictive facility SELECT policies. Authenticated DML revocation is therefore an important part of the live protection. Preserve it; do not re-grant direct writes as a workaround.

## Required next actions

1. Keep authenticated DML revoked on insurance cases, triage assessments and medication administrations.
2. Correct the candidate's triage function signature only after confirming the intended 14-argument API and all frontend/offline callers; do not create an unused 15-argument overload to make the migration compile.
3. Add a migration static contract that resolves every function signature named in REVOKE/GRANT statements against the expected schema contract.
4. Add ACL regression tests for direct DML denial and authenticated-only RPC execution.
5. Review the current triage and medication RPC bodies for role, patient/facility, test-mode, encounter-state, idempotency and audit guarantees before making any functional changes.
6. Preserve the current pinned search paths and avoid restoring candidate function definitions.
7. Reconcile both candidate provenance and hosted ledger identity before any migration history repair.
8. Test clean bootstrap and hosted-upgrade paths separately on disposable PostgreSQL 17/Supabase.

## Execution boundary

All inspection was read-only. No triage, medication, insurance, patient, or encounter row contents were queried. No SQL, privileges, policies, functions, triggers, or migration ledger entries were changed. No migration was renamed, replayed, applied, or deleted. The collision remains unresolved.
