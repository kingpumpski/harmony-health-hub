# Database compatibility repair

- [ ] Verify the deployed migration ledger, missing tables and columns, and refresh generated types (blocked: Cloud database unavailable).
- [ ] Reconcile duplicate migration versions against the deployed ledger (blocked: Cloud database unavailable; do not renumber applied history blindly).
- [x] Repair migration validation controls and expand laboratory schema checks (live SQL tests await database access).
- [x] Resolve verified Dental, emergency/department refresh, role-label, and notification dependency errors; run relevant repository tests.
- [ ] Resolve remaining generated-schema compilation errors and verify authenticated clinical flows (blocked: Cloud database unavailable).