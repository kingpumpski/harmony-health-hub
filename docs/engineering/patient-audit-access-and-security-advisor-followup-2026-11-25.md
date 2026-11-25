# Patient audit access and security-advisor follow-up — 2026-11-25

## Scope

Read-only hosted catalog, RLS policy, ACL and Supabase security-advisor review of
canonical project `ygqoptvezotdqhtimdkr`. No audit rows or patient data were read.
No schema, data, or Auth configuration was changed.

## Patient audit tables: confirmed overbroad boundaries

Both `public.patient_audit` and `public.patient_audit_log` have RLS enabled.
However, the effective table ACLs grant anon and authenticated SELECT on both
tables, and authenticated also has INSERT, UPDATE and DELETE table privileges.
The lack of an anon row policy means the observed anon SELECT grant does not by
itself prove anon can read rows; do not report it as confirmed row exposure.
Likewise, authenticated direct writes are constrained by RLS policies, but the
table ACL is broader than required and should be reduced after verifying every
application callsite.

Policy differences:
- `patient_audit`: authenticated SELECT policy is admin-only.
- `patient_audit_log`: authenticated SELECT policy allows all clinical staff or
  admins, with no facility predicate in the observed policy.
- `patient_audit_log` also has admin-only INSERT/UPDATE/DELETE policies.

The patient audit log is therefore a priority for facility-scoped read authorization.
A clinical role should not gain visibility of every facility's patient change
history merely by belonging to clinical staff. Define a narrowly scoped platform
audit role only if cross-facility audit is a documented requirement.

## Required forward repair

1. Trace application reads/writes, triggers, RPCs, and audit review screens for
   both audit tables before revoking direct client operations.
2. Keep required SELECT access through a facility-aware, audited RPC or an
   equivalent RLS predicate joining the audited patient to the caller's active
   facility. Make cross-facility audit access an explicit platform permission.
3. Revoke anon privileges and authenticated direct INSERT/UPDATE/DELETE unless
   a verified client callsite requires them. Prefer server-owned trigger/RPC
   writes with immutable audit provenance.
4. Review both audit tables and their triggers for duplicate capture and
   full-row OLD/NEW JSON retention. Minimize sensitive field capture, restrict
   access, and define retention under the organization's governance requirements.
5. Add regression tests for same-facility reads, cross-facility denial, platform
   audit access, anon denial, direct mutation denial, and trigger/RPC write paths.

Do not drop either audit table or merge the two stores until dependencies,
retention obligations, and historical lineage are fully mapped.

## Supabase security advisor snapshot

Observed at 2026-11-25 14:38 UTC:

- 2 INFO findings: RLS enabled without policies on
  `lab_test_group_items` and `lab_test_groups`. These are intentionally
  RPC-only in the application and historical migration revokes direct table
  access. Do not add permissive policies to silence the advisor; reduce excess
  grants after verifying the RPC path.
- 1 WARN: `public.ensure_updated_at()` has no fixed function search_path. It is
  used as a simple trigger function; a forward migration can set an empty
  search_path after a regression test confirms its body relies only on builtins
  and NEW row fields.
- 279 WARN findings: authenticated users can execute SECURITY DEFINER functions
  in the public schema. This is an inventory signal, not proof that all 279 are
  vulnerabilities: many are intended authenticated RPCs. Review exact function
  signatures, auth/role/facility checks, search_path and grant provenance; do not
  blanket-revoke or switch all functions to INVOKER.
- 1 WARN: leaked-password protection is disabled in Supabase Auth. This is an
  Auth project setting, not a SQL migration. Enablement requires an authorized
  project administrator and compatibility/rollout review; no setting was changed.

## Existing facility-boundary issues remain

The separate facility-boundary workspace report documents confirmed
SECURITY DEFINER read gaps in maternity, department queue, pharmacy, laboratory,
imaging, canteen and operational workspace functions. These must be repaired
with forward-only, regression-tested changes. Queue lineage must be reconciled
before strict facility filtering because existing queue/service-order facility
values are NULL.

## Verification boundary

All findings above come from read-only catalog, policy and advisor queries.
No audit row content was inspected, no Auth setting was modified, no migration
was generated or applied, and no production data was changed.
