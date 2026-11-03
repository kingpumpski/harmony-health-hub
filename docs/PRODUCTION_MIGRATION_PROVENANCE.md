# Production migration provenance register

**Candidate evidence only — NOT VERIFIED**

**Project reference:** `ygqoptvezotdqhtimdkr`  
**Observation date:** 2026-11-03  
**Production migration ledger:** 417 entries

## Canonical baseline entries

| Production version | Name | Original SQL recovered | Mapping status |
|---|---|---:|---|
| `20260916002251` | `canonical_remote_schema` | No | Unverified |
| `20260916003113` | `fix_start_imaging_order_queue_contract` | No | Unverified |

These versions are present in the current production migration ledger. The original SQL for both is not present in the reviewed repository evidence. Neither entry is approved for baseline reconstruction or migration repair.

## Evidence archive comparison

The attached reconciliation evidence archive was captured from fix-branch commit `31645d93` on 2026-11-02. It records:
- 661 local migration files
- 417 remote migration ledger entries
- 80 exact local/remote version overlaps
- 581 local-only versions
- 337 remote-only versions

The archive's local Supabase migration-history command failed to connect to `127.0.0.1:54322`; therefore it does not establish a successful local replay. The remote ledger was available. Current read-only Supabase inspection on 2026-11-03 again returned 417 applied production migrations.

## Candidate name matches for renamed local migrations

The following local migration names have same-name candidates in the production ledger under different remote versions. These are *not* approved mappings; matching names do not prove identical SQL or equivalent effects.

| Local candidate file | Remote version | Remote ledger name |
|---|---:|---|
| `20260925200001_notification_inbound_email_store.sql` | `20260925205248` | `20260925200000_notification_inbound_email_store` |
| `20260929100001_insurance_company_master_data.sql` | `20260929063756` | `20260929100000_insurance_company_master_data` |
| `20260929103001_service_catalogue_department_control.sql` | `20260929063454` | `20260929103000_service_catalogue_department_control` |
| `20260929150002_patient_canonical_insurer_linkage.sql` | `20260929081044` | `20260929150000_patient_canonical_insurer_linkage` |
| `20260929200001_role_dashboard_kpi_cleanup.sql` | `20260929141826` | `20260929200000_role_dashboard_kpi_cleanup` |
| `20260929203001_harden_security_definer_read_workspace_paths_batch6.sql` | `20260929143830` | `20260929203000_harden_security_definer_read_workspace_paths_batch6` |
| `20261002130001_scope_appointment_workflows_to_active_facility.sql` | `20261002052916` | `20261002130000_scope_appointment_workflows_to_active_facility` |
| `20261002132501_pharmacy_global_category_edit.sql` | `20261002132256` | `20261002132500_pharmacy_global_category_edit` |

The other 15 renamed migration names in the 23-file duplicate-version normalization tranche had no same-name candidate in the current production ledger. They may be pre-baseline history, represented by different migrations, or genuinely pending. Each requires SQL identity and schema-effect review.

## Required evidence before verification

For each baseline entry and every local/remote candidate mapping, record:
1. Exact source commit and file path.
2. SHA-256 of the candidate SQL file and any recovered deployed SQL.
3. Evidence of the remote version/name and deployment time.
4. Object-level schema/function/policy comparison proving equivalence or documenting intentional divergence.
5. A reviewer-approved disposition: exact mapping, baseline-covered, already-applied equivalent, pending, or obsolete.
6. Explicit approver and reviewed commit.

Do not use `supabase migration repair`, edit `supabase_migrations.schema_migrations`, fabricate baseline SQL, or run production `supabase db push` to force the histories together.

## Gate state

This register is deliberately marked candidate-only. The two canonical baseline entries retain `mappingStatus: unverified`, and `supabase/production-migration-baseline.json` remains `status: unreconciled` with `productionPushAllowed: false`.
