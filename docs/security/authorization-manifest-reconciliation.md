# Authorization manifest reconciliation

The authorization review is represented by three machine-readable inventories:

1. **High-risk RPC inventory** — identifies RPCs requiring explicit authorization review.
2. **Patient/facility boundary manifest** — identifies patient-scoped workflows whose tenant lineage is not yet enforced.
3. **SECURITY DEFINER review manifest** — defines the broader security requirements for privileged RPCs.

The reconciliation contract prevents these inventories from drifting apart.

## Required invariants

- Every patient/facility workflow is also present in the high-risk RPC inventory.
- Every patient-scoped high-risk RPC is present in the patient/facility manifest.
- Every high-risk RPC requiring isolated regression is explicitly patient-scoped.
- High-risk review dimensions remain represented in the SECURITY DEFINER review policy.
- Patient-scoped isolation evidence remains explicitly `not_run` until genuine isolated testing exists.
- The anonymous SECURITY DEFINER EXECUTE requirement remains zero.

Run:

`npm run test:authorization-manifest-reconciliation`

This is a repository consistency control. It does not claim runtime authorization isolation.
