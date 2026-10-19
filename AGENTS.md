# Project rules

- Reconcile migration identities with the deployed ledger before renumbering historical files; applied versions are provenance and must not be guessed.
- Verify laboratory schema compatibility through the database contract and repository contract; static tests cannot establish deployed schema state.
- Keep Deno npm dependency resolution configured per notification function so edge-function checks do not depend on frontend node_modules.