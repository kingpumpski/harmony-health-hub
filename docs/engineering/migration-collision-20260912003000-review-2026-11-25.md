# Migration collision group review — 20260912003000

**Review date:** 2026-11-25  
**Hosted project:** `ygqoptvezotdqhtimdkr`  
**Scope:** read-only source and canonical catalog comparison

## Candidates

| Candidate | Feature |
|---|---|
| `20260912003000_phase2_pharmacy_procedure_imaging_gates.sql` | Imaging order/payment gate, procedure charge column, medication/procedure payment trigger |
| `20260912003000_phase4_triage.sql` | Triage assessment persistence, indexes, RLS policies and updated-at trigger |

The two files have different SHA-256 fingerprints in the collision inventory. Neither exact version prefix appears in the captured 417-entry hosted migration ledger. That absence is not proof that the SQL was never executed under another identity or manually.

## Static overlap review

No same-named table is explicitly created by both candidates:
- Phase 2 creates `imaging_orders`, alters `procedure_notes`, and creates/replaces `create_imaging_order_with_payment_gate` and `enforce_service_payment_gate`.
- Phase 4 creates `triage_assessments`.

They do share dependencies on existing patient/auth/clinical helper objects, and Phase 2 touches `medication_administrations` via a trigger. This looks like two separate feature tracks rather than two competing versions of one feature. It is not sufficient evidence to renumber either file.

## Canonical catalog comparison

Both feature families are present in the canonical database.

### Imaging

The live `imaging_orders` table contains the candidate's core fields plus later additions including:
- `facility_id`
- `started_at`
- `completed_at`
- `acknowledged_at`
- `acknowledged_by`

The live `procedure_notes.charge_amount` column also exists.

The live `create_imaging_order_with_payment_gate` function is materially hardened beyond the original candidate:
- checks authentication and explicit clinical/administrative roles;
- verifies patient is active and validates patient facility context;
- checks optional encounter belongs to the patient, is not closed, and matches facility;
- inserts facility attribution on imaging and service orders;
- pins an empty search path.

This is evidence that later forward hardening exists in the live schema. It does not prove which historical migration file was applied.

### Triage

The live `triage_assessments` table exists with the expected core assessment fields and later `bmi` and `facility_id` columns.

There is a notable difference from the original candidate: several vital-sign fields that the candidate declared NOT NULL are nullable in the live catalog. The original candidate's check constraints and current live constraint definitions must be compared before any replay decision. Do not replay the original CREATE TABLE definition over the evolved live table and assume `IF NOT EXISTS` reconciles its nullability or checks.

## Disposition

**Provisional classification: both feature tracks appear required; no winner selected.**

The canonical schema contains both imaging and triage feature families. The imaging RPC and both table schemas have evolved since the candidate bodies. Therefore:
- preserve both source files unchanged;
- do not delete either file;
- do not renumber either file based solely on this comparison;
- recover original Git/deployment provenance and all subsequent migrations affecting these objects;
- compare full live constraints, indexes, policies, triggers, grants, function ACLs and function bodies;
- replay the two feature tracks plus later hardening on disposable PostgreSQL 17/Supabase after the baseline/bootstrap path is agreed.

This group is a useful example of why a collision must not be resolved by selecting one candidate: the files appear to represent distinct required modules, while the authoritative live schema contains later changes that neither original file fully describes.
