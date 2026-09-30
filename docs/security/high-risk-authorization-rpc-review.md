# High-risk authorization RPC inventory

This inventory complements the SECURITY DEFINER review. It identifies authenticated RPCs where a successful source review is not sufficient to establish tenant isolation.

## Review dimensions

Every inventoried function is reviewed against:

- authentication;
- role/permission;
- facility boundary;
- patient/resource ownership;
- workflow state;
- concurrency/row locking;
- explicit EXECUTE grants;
- read path;
- mutation path.

Patient-scoped functions additionally require isolated cross-facility regression evidence.

## Status meaning

- `source_contract_reviewed`: repository-level authorization invariants are explicitly represented by a source contract, but this does not claim cross-facility runtime isolation.
- `requires_isolated_regression`: runtime evidence is still required before the function can be considered tenant-enforced.

The companion isolation evidence remains `not_run` until a genuine isolated Supabase environment and non-admin Facility A/B fixtures are available.

This inventory intentionally does not revoke authenticated EXECUTE or convert functions to SECURITY INVOKER merely because they are SECURITY DEFINER. Each function must be evaluated on its actual authorization boundary.
