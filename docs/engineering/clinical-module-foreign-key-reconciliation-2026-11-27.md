# Clinical module foreign-key reconciliation — 2026-11-27

## Scope

The relationship contract and the 2026-11-25 read-only catalog review identify four missing foreign keys that can leave clinical records detached from their parent records. The reviewed catalog reported zero orphans for all four links, but the repair does not rely on that historical snapshot.

## Forward-only repair

Added `supabase/migrations/20261127102000_reconcile_clinical_module_foreign_keys.sql`.

| Child reference | Parent | Delete behavior | Reason |
|---|---|---|---|
| `emergency_cases.patient_id` | `patients.id` | SET NULL | Preserve the emergency encounter record if a patient identity is removed; the case remains auditable. |
| `transfusion_records.patient_id` | `patients.id` | RESTRICT | Do not delete a patient while transfusion history still references them. |
| `medication_administrations.prescription_id` | `prescriptions.id` | SET NULL | Preserve the administration record if its prescription is removed. |
| `ward_beds.admission_id` | `admissions.id` | RESTRICT | Prevent deleting an admission while a bed still references it; release/transfer the bed through the inpatient workflow first. |

For each relationship, the migration:
- Checks for orphan references and aborts with a specific error instead of silently deleting or rewriting clinical records.
- Adds the FK as `NOT VALID` and then validates it, making the enforcement step explicit.
- Creates a supporting index for child-side lookups and referential checks.
- Notifies PostgREST to reload its schema cache.

The constraints are added idempotently by their canonical names. The existing exception registry remains intact until a database replay and regenerated Supabase types prove that all four relationships exist.

## Data-retention and dummy-data note

The user's confirmation that current project data are disposable permits a future controlled clean reset/reseed of an explicitly identified development database if needed. It is not a reason to delete clinical history automatically in a migration. These four FK repairs intentionally preserve records and fail closed if unexpected orphans are present.

## Verification boundary

`scripts/clinical-module-fk-repair-contract.mjs` verifies the SQL source, preflight checks, delete semantics, validation statements, and supporting indexes. The contract is included in `npm run test:migration-parity`.

This is source-level verification only. The migration has not been executed against PostgreSQL. The global migration identity preflight still reports 21 duplicate historical versions, so the clean replay remains blocked. No database was accessed or modified.
