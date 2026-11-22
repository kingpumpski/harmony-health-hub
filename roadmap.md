# Database compatibility repair

- [ ] Reconcile all migration parity discrepancies against current deployed histories (blocked: live migration history unavailable).
- [ ] Restore fail-closed migration contract validation and comprehensive collision diagnostics; verify regression tests.
- [ ] Record migration parity evidence, replay limitations, and deployment next steps.
- [ ] Verify the deployed migration ledger, missing tables and columns, and refresh generated types (blocked: Cloud database unavailable).
- [ ] Reconcile duplicate migration versions against the deployed ledger (blocked: Cloud database unavailable; do not renumber applied history blindly).
- [x] Repair migration validation controls and expand laboratory schema checks (live SQL tests await database access).
- [x] Resolve verified Dental, emergency/department refresh, role-label, and notification dependency errors; run relevant repository tests.
- [ ] Resolve remaining generated-schema compilation errors and verify authenticated clinical flows (blocked: Cloud database unavailable).