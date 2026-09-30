# Authorization boundary best practices

Harmony Health Hub treats authorization as an application security boundary rather than a UI concern. Protected workflows should combine authentication, role or permission checks, resource ownership, workflow state, concurrency controls, and explicit function execution privileges.

## SECURITY DEFINER rules

Security-definer functions are retained only where they provide a deliberate authorization or RLS boundary. They must:

- authenticate the caller;
- perform explicit role, ownership, or facility checks appropriate to the operation;
- use a safe explicit `search_path`;
- schema-qualify database objects;
- use row locks for sensitive state transitions where concurrency matters;
- avoid trusting user-editable metadata for authorization;
- have explicit EXECUTE grants rather than relying on PUBLIC defaults.

## Production safety

Do not resolve Supabase Security Advisor findings by blindly revoking all authenticated execution from application RPCs. Review each callable function against its intended workflow and privilege boundary, then encode the decision in a regression contract.

## Inpatient bed facility boundary

The canonical `transfer_patient_ward_bed_workflow` requires a valid active-facility context for non-admin callers and rejects destination/source beds outside that facility. Admins retain cross-facility troubleshooting authority. The migration is validated transactionally against the live schema and remains subject to the existing production migration approval gate.

## Exposed views

Public-schema views are treated as security boundaries, not as harmless read-only projections. Every exposed view must either:

- use PostgreSQL `security_invoker = true` so the querying user's underlying-table permissions and RLS apply; or
- have explicit Data API privilege revocation when it is not intended for `anon`/ `authenticated`.

The repository contract `test:public-view-security` prevents newly introduced public views from bypassing this review.

## Function exposure and defaults

Function execution is opt-in for protected application RPCs. The repository maintains explicit privilege manifests and migration contracts for authenticated execution and PUBLIC/anon revocation. Default privileges are separately hardened so newly created public-schema functions do not silently become Data API-callable.
