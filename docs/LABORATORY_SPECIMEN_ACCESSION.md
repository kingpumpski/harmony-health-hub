# Laboratory specimen accession and rejection

## Scope
This repository change adds specimen accession records to the laboratory collection transaction and provides a governed specimen-rejection workflow. It is not a validated barcode-printing integration or a complete laboratory information system.

## Workflow
1. An authorized user collects an order only after the existing payment/release gate succeeds.
2. The same database transaction creates a unique specimen accession and barcode value, records the collecting user/time, and advances the order to `sample_collected`.
3. The laboratory UI shows accession, barcode value, specimen type, collection time, and rejection history.
4. A laboratory technician or administrator may reject a collected/received specimen before result entry, with a required reason. The specimen record remains rejected and auditable; the order returns to `ordered` for recollection.
5. A recollected specimen receives a new accession and links to the most recent rejected specimen through `recollection_of_id`.

## Security
- Direct table access is revoked from public, anonymous, and authenticated client roles.
- Mutations use SECURITY DEFINER RPCs with an empty search path, explicit authentication, clinical-role checks, active-facility boundaries, and the existing payment gate.
- Specimen reads are returned by a facility-scoped RPC with department-aware role checks.
- Rejection requires a 3–1000 character reason and records an audit event.

## Limitations and rollout
- The barcode value is a stable accession string suitable for a future barcode label encoder; this change does not print labels or integrate a scanner.
- Receipt, processing, aliquot, chain-of-custody, QC, analyzer interfaces, critical-value escalation, and result correction/versioning remain follow-up work.
- Do not apply this migration to the connected Supabase project without explicit approval and migration-ledger reconciliation.
- Clinical and laboratory leadership should approve specimen type mappings, collection/rejection policy, and operating procedures before live use.
- Required automated checks and a non-production workflow test must pass before merge or deployment.
