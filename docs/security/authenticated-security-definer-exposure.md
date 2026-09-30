# Authenticated SECURITY DEFINER exposure

## Policy

Harmony Health Hub intentionally uses authenticated SECURITY DEFINER RPCs for server-authoritative clinical, billing, notification, reporting, and workflow boundaries. Supabase's Security Advisor lint for authenticated-callable SECURITY DEFINER functions is therefore not, by itself, evidence that an RPC should be revoked.

Every newly introduced public-schema SECURITY DEFINER function must nevertheless have an explicit execution contract:

- SECURITY DEFINER is used only where the workflow requires an elevated database boundary.
- The function must set an explicit search_path; new definitions use an empty search path and schema-qualified references.
- PUBLIC and anon execution are explicitly revoked.
- authenticated execution is explicitly granted.
- Authorization remains inside the function: authentication, role/permission, resource ownership, facility boundary where authoritative lineage exists, workflow state, and concurrency controls are reviewed separately.
- Patient/facility isolation is not considered complete until an isolated two-facility regression fixture passes.

## CI guard

scripts/authenticated-security-definer-exposure-contract.mjs scans migrations after the appointment-hardening baseline and rejects a new authenticated SECURITY DEFINER function that lacks explicit PUBLIC/anon denial and authenticated execution.

This is deliberately additive to the function-specific authorization contracts. It prevents a future migration from accidentally introducing another exposed privileged RPC while preserving legitimate application RPCs.

## Current production interpretation

The current Supabase Security Advisor reports a large set of authenticated-callable SECURITY DEFINER functions (212 findings in the 2026-09-30 live audit). These are existing application RPCs and are not being mass-revoked because doing so would break intended workflows. The correct remediation path is function-by-function review and explicit least-privilege contracts, followed by moving functions to SECURITY INVOKER or a non-exposed schema when the elevated boundary is not required.

Supabase recommends SECURITY INVOKER by default and an empty search_path for functions that must use SECURITY DEFINER.

## Rollout gate

Do not apply the patient/facility tenancy enforcement migration to production until:

1. a non-production Supabase environment contains two non-admin users in different facilities;
2. the same patient is explicitly linked to only the intended facility;
3. cross-facility reads and mutations are denied;
4. same-facility workflows continue to succeed;
5. concurrency/row-lock regression tests pass;
6. Security Advisor is re-run after migration application.
7. Auth leaked-password protection is reviewed separately; it is currently reported as disabled in the live project and is not changed by this migration branch.
