# Authorization boundary best practices

## Patient/facility tenancy

Harmony Health Hub must not infer a patient's facility from creator, recorder, appointment, or historical membership data when that lineage is ambiguous.

The tenancy foundation introduces an explicit `patient_facility_access` relationship and an active-facility resolver. Patient-scoped workflows should use the assertion helper once their lineage is validated.

### Enforcement gate

A patient-scoped function is classified in `scripts/patient-facility-boundary-manifest.json` as:

- `pending_tenancy_enforcement`: authorization is intentionally not yet enforced by the new patient/facility boundary.
- `enforced`: the function must call the patient/facility authorization helper and has passed isolated cross-facility regression tests.
- `exempt`: documented as not requiring the patient/facility boundary.

No function may be changed to `enforced` merely because the code compiles. The transition requires:

1. Two non-admin users belonging to different facilities.
2. Explicit patient-to-facility fixtures in an isolated Supabase environment.
3. Allowed access from the patient's linked facility.
4. Denied access from the other facility.
5. Regression coverage for both read and mutation paths.
6. Confirmation that admin and IT-admin troubleshooting access remains intact.
7. Supabase security and performance advisor review after the migration.

### SECURITY DEFINER rules

Security-definer functions are retained only where they provide a deliberate authorization or RLS boundary. They must:

- authenticate the caller;
- perform explicit role/facility/ownership checks appropriate to the operation;
- use a safe explicit `search_path`;
- schema-qualify database objects;
- use row locks for sensitive state transitions where concurrency matters;
- avoid trusting user-editable metadata for authorization;
- have explicit EXECUTE grants rather than relying on PUBLIC defaults.

### Production safety

Do not bulk-link ambiguous historical patients. Do not enable patient-wide cross-facility RLS until the tenancy fixtures prove that the model preserves legitimate workflows.


## Exposed views

Public-schema views are treated as security boundaries, not as harmless read-only projections. Every exposed view must either:

- use PostgreSQL `security_invoker = true` so the querying user's underlying-table permissions and RLS apply; or
- have explicit Data API privilege revocation when it is not intended for `anon`/ `authenticated`.

The repository contract `test:public-view-security` prevents newly introduced public views from bypassing this review. This follows Supabase guidance that views can otherwise bypass RLS when created by a privileged owner. 

## Function exposure and defaults

Function execution is opt-in for protected application RPCs. The repository maintains explicit privilege manifests and migration contracts for authenticated execution and PUBLIC/anon revocation. Default privileges are separately hardened so newly created public-schema functions do not silently become Data API-callable.

The remaining authenticated SECURITY DEFINER advisor findings are tracked as intentional application RPCs pending individual authorization review; the project does not resolve the warning by blindly revoking all authenticated execution, because that would break legitimate workflow boundaries.
