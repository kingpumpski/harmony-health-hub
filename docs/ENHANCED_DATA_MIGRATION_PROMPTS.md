# Enhanced Clinical Data Migration — Implementation Prompts

This file replaces the original ten prompts as the repository-aware implementation contract for Harmony Health Hub. The prompts are ordered; execute them in one feature branch when safe, but do not bypass repository gates to achieve a superficial green build.

## Prompt 1 — Inspect repository and establish scope

Act as the senior healthcare data engineer for `kingpumpski/harmony-health-hub`. Read `AGENTS.md`, current `DataImport.tsx`, all migration-related migrations/RPCs, generated Supabase types, route/role guards, import parser utilities, package scripts, CI workflows, and open PRs before editing. Identify existing capabilities and gaps. Reuse the existing administrator-only Data Import & Migration Workspace and governed legacy reconciliation workflow. Do not create a second migration subsystem or infer schema from UI names.

Deliver a requirements and traceability matrix with each capability classified as **implemented**, **being added in this PR**, **deferred**, or **blocked by environment**. Keep this PR scoped to safe file ingestion and staging. Scheduled REST API pulls, SFTP ingestion, SQL-dump execution, automated clinical promotion, and native-table writes are separate future work requiring server-side credentials, threat modelling, schema mapping, and approval.

## Prompt 2 — Source formats and canonical records

Support existing CSV/XLS/XLSX workflows and add JSON records/FHIR R4 Bundle, generic XML records, and HL7 v2 message parsing for **legacy clinical record staging only**. Reject unknown extensions, malformed payloads, empty files, files above 25 MB, and more than 10,000 normalized records. Validate content instead of trusting file extensions. Keep raw source content in structured `raw_record` metadata and preserve source system, source patient key, source record identifier, record type, event timestamp, author, department, encounter reference, and concise summary where present.

Do not claim that parsing means full standards conformance. Document unsupported FHIR resource profiles, XML variants, HL7 segments, code-system transformations, API/SFTP connectors, SQL backup restoration, and streaming/resumable upload as future work until implemented and tested.

## Prompt 3 — Schema and field mapping

Before adding schema, inspect the actual migration history and canonical RPC signatures. Map the canonical legacy staging shape to `data_migration_batches`, `data_migration_rows`, and `legacy_clinical_records`. Do not write imported clinical data directly into `patients`, `encounters`, `appointments`, `lab_results`, `prescriptions`, or billing tables. Preserve the source system and identifiers. Use forward-only, timestamp-unique migrations, safe constraints, indexes only where justified, and update generated types only using the project's verified process.

## Prompt 4 — Ingestion UX and staging

Extend the existing administrator-only upload workspace. Make accepted file types depend on the selected entity: reference/master-data import retains its currently supported formats; legacy clinical records can use CSV, XLS/XLSX, JSON/FHIR Bundle, XML, and HL7 v2. Show source-system metadata, parsed row count, safe preview, field/row validation feedback, and an explicit staging action. A dry run must not write data. No parser may call a database write directly. All staged records must go through existing server-authorized migration RPCs and remain in the reconciliation lifecycle.

## Prompt 5 — Validation, matching, and transformation

Add deterministic format parsing and row-level validation with actionable, PHI-safe messages. Normalize field names and timestamps only when their formats are recognized. Preserve original codes and raw records; do not invent ICD-10, SNOMED, LOINC, medicine, unit, currency, or facility mappings. Patient matching must use the existing server-side candidate workflow and require explicit reconciliation for ambiguous candidates. Never auto-merge patients or silently assign missing facility attribution.

## Prompt 6 — Backend and transaction contract

Use existing database functions after verifying their current definitions, permissions, RLS, and grants. The server remains authoritative for staging, validation, approval, and promotion. Re-runs must be idempotent or explicitly rejected; no client-side claim of atomicity unless the database RPC provides it. Database changes require migration filename/dependency validation, clean replay, schema/security contracts, and an audit review. Never weaken RLS or broad grants to fix import failures.

## Prompt 7 — Frontend, accessibility, and provenance

Preserve current UI conventions and role boundaries. Provide keyboard-accessible file selection, clear format help, loading/empty/error states, row counts, and a safe preview that avoids dumping sensitive clinical payloads. Keep all workflow actions explicit and visible; do not automatically promote after parsing. Clinicians may view approved legacy continuity records only through existing access controls. Provenance must remain available to auditors and clinicians where the current product exposes it.

## Prompt 8 — Security, privacy, and audit

Treat all uploads as untrusted. Enforce size/row limits, safe parsing, strict format detection, no XML external entity resolution, no execution of SQL dumps, no PHI in console logs or telemetry, and no sensitive payloads in test fixtures. Validate role access at both UI and database layers. Record batch/source provenance and use existing audit mechanisms. Compliance claims must be mapped to verified controls; do not assert HIPAA/GDPR compliance from a checklist alone. For Ghana deployment, identify applicable local legal and data-protection review as a release dependency.

## Prompt 9 — Tests, rollout, and acceptance

Add regression tests for each supported format, malformed/empty/oversized input, FHIR Bundle extraction, HL7 segment mapping, source-format metadata, and preservation of the existing spreadsheet parser. Add contract checks that legacy clinical imports still use governed staging and never directly insert into native clinical tables. Run npm ci, relevant parser/contract tests, lint, TypeScript typecheck, production build, migration uniqueness/dependency checks, clean migration replay where available, and inspect the latest required CI runs for the exact PR head SHA. Report infrastructure-blocked checks as unverified.

Acceptance requires: malformed input is rejected before writes; supported formats normalize to the same staging contract; existing CSV/XLS/XLSX flows remain intact; only administrators can upload; parsing alone never mutates the database; staged records retain provenance; and all required quality/build checks pass on the exact PR head.

## Prompt 10 — Master orchestration and PR lifecycle

Implement the smallest complete feature consistent with this contract. Keep a defect ledger and explain every assumption. Create a dedicated feature branch and a non-draft PR against `main` only after code review and successful development/build checks. If checks are queued, failing, unavailable, or require external Supabase credentials, state that clearly; do not claim a successful build or merge the PR. Do not merge unless explicitly requested. Include files changed, schema implications, tests actually run, CI run links/statuses, commit SHA, limitations, rollback considerations, and the next safe step in the PR description.
