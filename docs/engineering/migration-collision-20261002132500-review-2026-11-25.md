# Migration collision review: 20261002132500

Updated: 2026-11-25

## Scope and decision

Reviewed both candidates sharing version `20261002132500`:

- `20261002132500_patient_hub_read_rpc_get_compatibility.sql`
- `20261002132500_pharmacy_global_category_edit.sql`

The exact version is absent from the canonical hosted migration ledger. The Patient Hub RPCs named by the candidate are present and currently marked STABLE. The pharmacy assignment/update functions are present, but the live update function body materially differs from the candidate.

**Disposition:** preserve both original files. Do not rename, delete, replay, or mark either candidate applied. Current state supports that the intended GET compatibility is present, but it does not prove this migration source created that state. The pharmacy candidate must not be replayed as-is because it would restore stricter stock-price/reorder requirements than the current live function intentionally permits.

## A. Patient Hub GET compatibility

The candidate changes six read RPCs to STABLE so PostgREST can invoke them over GET:

- `get_patient_appointments(uuid,integer)`
- `get_patient_admission_history(uuid)`
- `get_patient_hub_clinical_snapshot(uuid)`
- `get_patient_current_treatment_snapshot(uuid,uuid)`
- `get_patient_bmi_context(uuid)`
- `get_attending_patient_history(uuid,uuid)`

All six functions exist in the hosted catalog and were observed with volatility `s` (STABLE). The Patient Hub frontend's read-only GET compatibility contracts are also present in the repository.

There is a security nuance: `get_attending_patient_history(uuid,uuid)` currently uses `search_path = pg_catalog, public`, while the other five inspected functions use an empty search path. Its body includes `assert_patient_facility_read_context(_patient_id)`; retain that explicit facility assertion and review the broader search path as a separate hardening item. Do not change function volatility or search path solely to make the historical candidate appear applied.

The catalog state proves current volatility, not the provenance or exact execution of this migration. Other migrations or direct DDL may have set the same properties.

## B. Pharmacy global category edit

The candidate replaces `update_pharmacy_inventory_item(...,text,numeric,numeric,text)` and preserves an audited facility assignment RPC for legacy stock.

The live `assign_unattributed_pharmacy_inventory(uuid,text)` exists as SECURITY DEFINER with an empty search path. Its body requires an admin/system-superuser role, active destination facility, a reconciliation reason, and audits the facility assignment.

The live `update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text)` also exists as SECURITY DEFINER with an empty search path and updates only an active stock item belonging to the caller's active facility. It updates the shared catalogue category only when a catalogue link exists, and records an audit event.

However, the live body is materially different from the candidate:
- Candidate rejects positive stock unless expiry, positive unit price, and positive reorder level are configured.
- Live body explicitly allows zero price and zero reorder values for test/preconfigured stock, while still requiring an expiry date for positive stock.
- Live body also writes the editable drug-name, generic-name, strength and form fields; the candidate's update body does not update those fields in the same way.

This is a deliberate behavior difference evidenced by the live function comments/body. Do not restore the candidate body without a current product/business requirement and a reviewed migration. Keep facility scoping and audit behavior.

## C. Ledger and provenance

The canonical ledger query returned no row for version `20261002132500`. Current function volatility and function bodies cannot establish whether either exact candidate ran, whether the same statements were applied under another version, or whether later migrations replaced the original definitions.

Required evidence before classifying the duplicate group:

1. Recover deployment logs or original applied SQL for both candidates, including alternate hosted version identities.
2. Compare exact source fingerprints and the six Patient Hub function definitions/ACLs.
3. Confirm the pharmacy UI's zero-price/zero-reorder behavior is intentional and governed; test both configured and preconfigured stock states.
4. Compare all candidate ACL and function-signature effects with the live catalog.
5. Test clean-install bootstrap and existing-hosted upgrade separately on disposable PostgreSQL 17/Supabase.

## Required next actions

1. Preserve both historical files unchanged pending provenance recovery.
2. Retain STABLE volatility for the six Patient Hub read RPCs, with GET/POST compatibility regression coverage.
3. Review the attending-history search path separately; do not weaken its facility assertion.
4. Keep the current facility-scoped pharmacy update implementation unless product owners approve a different stock-configuration rule.
5. Add regression coverage for active-facility-only pharmacy updates, category edits, audit attribution, and valid zero-price/preconfigured stock behavior.
6. Continue duplicate-version reviews without bulk renaming or suppression.

## Execution boundary

The canonical Supabase inspection was read-only and limited to migration-ledger identity, function volatility, function definitions and search-path metadata. No patient, admission, encounter, pharmacy inventory or prescription row contents were queried. No SQL, ACL, policy, function, trigger, schema object, or migration ledger entry was changed. No historical migration was renamed, replayed, applied, or deleted. No disposable replay was run because a local Supabase CLI/PostgreSQL/Docker environment is not available in this session. The collision remains unresolved.
