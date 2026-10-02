# Harmony Health Hub — Patient Hub and Pharmacy Test Release Checklist

Use this checklist to validate PR #271 before considering promotion. It is a test plan, not evidence that the project has passed production sign-off. At the time of the latest diagnostic check, the connected Supabase account exposed only the `harmony-health-hub` project; there was no separate Supabase test project available. The app's test mode is not a separate database. Do not treat it as database isolation.

## 1. Release gates

- [ ] Review PR #271 and confirm its diff contains only the intended Patient Hub compatibility/test changes.
- [ ] Wait for the GitHub **Quality** workflow to finish successfully, including typecheck, lint, regression contracts, and production build.
- [ ] Provision or identify a dedicated non-production Supabase project and record its project reference before applying migrations. Do not apply test migrations to the current production project.
- [ ] Confirm a current backup/recovery point and the normal migration approval process are in place.
- [ ] Apply the migration through the repository's approved Supabase migration workflow; do not manually edit production function definitions to work around the error.
- [ ] Do not promote to production until the same checks and a separately approved production migration have been completed.

## 2. Verify the read RPC volatility

After applying migrations to the test database, run this read-only query in the Supabase SQL Editor:

```sql
select
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  p.provolatile as volatility
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'get_patient_appointments',
    'get_patient_admission_history',
    'get_patient_hub_clinical_snapshot',
    'get_patient_current_treatment_snapshot',
    'get_patient_bmi_context',
    'get_attending_patient_history'
  )
order by p.proname, arguments;
```

For these read-only functions, `provolatile` should be `s` (STABLE). If a function is missing, appears more than once with unexpected signatures, or is not STABLE, stop and investigate the applied migration history before testing further.

**Latest live diagnostic (2026-10-02):** the six functions currently report STABLE. Supabase edge logs showed the three Patient Hub GET RPCs returning HTTP 200 at 09:26 UTC, while earlier requests at 05:20 UTC returned 405. Therefore the 405 was observed historically but was not reproducible in the latest check; do not claim this PR alone fixed it. Retest with the affected account and capture a fresh request if it recurs.

## 3. Patient Hub acceptance tests

Use a dedicated test patient assigned to the test facility. Do not use real patient data for routine acceptance testing.

- [ ] Sign in as a permitted non-privileged test user and select the facility that owns the test patient.
- [ ] Open the patient by hospital ID and confirm the profile loads.
- [ ] Confirm appointments, clinical history, and admissions load without a 405 response.
- [ ] Confirm a patient belonging to a different facility remains inaccessible to a non-privileged user.
- [ ] Confirm an unknown hospital ID produces a clear not-found state rather than stale data from a previous patient.
- [ ] Confirm a failed section reports its failure while other available sections remain usable.
- [ ] Repeat with the intended privileged test role and verify access remains auditable and within the documented role policy.

## 4. Encounter-start facility mismatch

A `Facility context mismatch` response is separate from Patient Hub GET compatibility. Latest database logs show `assign_active_facility()` raising during the encounter INSERT because the encounter's facility differs from `current_user_facility_id()` at trigger time. The current encounter-start function also requires the patient's facility to match the active facility. This points to an active-facility/context mismatch at write time; it is not a reason to weaken the trigger.

The current live database also has legacy rows with missing facility attribution (aggregate diagnostic: 10 appointments, 10 patients, and 10 encounters with null facility IDs; no appointment/patient or encounter/patient mismatches were found among rows with both IDs populated). These counts do not identify the affected test record. Reconcile only the specific test record through the approved audited workflow.

- [ ] Record the test user's active facility ID, patient ID and facility ID, appointment ID and facility ID, and any linked encounter ID and facility ID in an access-controlled admin diagnostic; do not paste patient identifiers into public issue comments or general logs.
- [ ] Compare those IDs using authorized, read-only diagnostics.
- [ ] Check whether the appointment belongs to the same patient and facility and whether it is in a startable status.
- [ ] If attribution is incorrect, use the project's approved, audited reconciliation workflow with an authorized administrator.
- [ ] Re-test encounter start and verify the resulting encounter retains the correct patient/facility lineage.

**Do not** remove facility checks, impersonate a different facility, or directly rewrite production records just to make encounter start succeed.

## 5. Pharmacy smoke tests (existing functionality; avoid duplicate implementation)

- [ ] Open Pharmacy and verify the page renders without a `ClinicalProgressBar is not defined` or store crash.
- [ ] Confirm global medication catalogue entries are distinct from facility-specific stock.
- [ ] Add a catalogue item to the test facility and confirm its initial quantity is zero.
- [ ] Confirm inventory quantities, price, expiry and reorder level are scoped to the selected facility.
- [ ] Open a test patient's dispensing view and verify allergies, diagnosis and prescribed medicines are shown correctly.
- [ ] Confirm dispensing is blocked when available stock is insufficient.
- [ ] Confirm an in-stock alternative can be selected and the substitution reason is captured where required.
- [ ] Test partial dispensing, barcode lookup, and the relevant NHIS/cash pricing path.
- [ ] Verify stock changes and dispensing records are persisted and correctly audited.

## 6. Evidence to attach to the PR

- [ ] Quality workflow run URL and final status.
- [ ] Test environment/project reference (never include service-role keys or secrets).
- [ ] Migration version and the read-only volatility query result.
- [ ] Acceptance-test results, including role and facility combinations.
- [ ] A concise account of any remaining failures and linked logs with tokens and patient-identifying data removed.

## Exit criteria

The change is ready for test sign-off only when the migration is applied in a dedicated test project, the Quality workflow passes, Patient Hub GET calls work for authorized test users, cross-facility isolation is preserved, and encounter-start lineage is verified. Passing source-level contracts alone is not production verification. Because no separate test project is currently available, do not describe the current shared production database as an isolated test environment.
