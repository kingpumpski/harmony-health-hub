# Isolated cross-facility authorization evidence

This contract is the gate for converting the patient/facility tenancy work from **pending** to **reviewed** or **enforced**.

## Required fixture

Use an isolated Supabase development/staging environment only:

- Facility A and Facility B.
- Non-admin User A has active membership only in A.
- Non-admin User B has active membership only in B.
- Patient A is explicitly linked to A.
- Patient B is explicitly linked to B.
- An admin fixture is available to verify the documented administrative exception.

Do not create these fixtures in production.

## Required regressions

The evidence manifest requires:

1. same-facility patient read allowed in A;
2. same-facility patient read allowed in B;
3. cross-facility patient read denied in A → B;
4. cross-facility patient read denied in B → A;
5. same-facility mutation allowed in A;
6. same-facility mutation allowed in B;
7. cross-facility mutation denied in A → B;
8. cross-facility mutation denied in B → A;
9. authorized admin cross-facility access preserved.

A status other than `not_run` is invalid unless every case has an observed result matching its expected result, a run identifier, execution timestamp, isolated database identifier, and evidence reference.

Run the repository contract with:

`npm run test:authorization-isolation-evidence`

The repository deliberately ships the manifest as `not_run`; it does not manufacture successful evidence.

## Transition policy

- **not_run**: isolated environment and regression have not been completed.
- **reviewed**: all required cases have matching recorded observations.
- **enforced**: reviewed evidence plus verified isolated fixture/identity provenance and no production fixtures.

Only after the evidence is complete should patient-scoped functions move from `pending_tenancy_enforcement` to `enforced`.
