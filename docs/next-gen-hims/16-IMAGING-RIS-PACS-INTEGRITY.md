# Imaging / RIS / PACS Integrity Boundary

## Purpose

The next-generation imaging boundary extends the existing `imaging_orders` workflow rather than creating a second imaging subsystem. It separates acquisition reconciliation from clinical report finalization.

## Server-authoritative controls

- Imaging acquisition requires an authenticated clinical staff member and an order already in `in_progress` state.
- Accession numbers and DICOM study UIDs are persisted on the canonical imaging order and protected by unique indexes.
- PACS references and image counts are retained as acquisition metadata.
- Acquisition is closed atomically under a row lock and records the responsible user and timestamp.
- A clinical imaging report cannot be finalized until acquisition has been reconciled as `acquired`.
- Report finalization is authenticated, row-locked, human-authoritative, and records the finalizing user and timestamp.
- A finalized report cannot be finalized a second time through the new workflow.
- Authenticated direct INSERT/UPDATE/DELETE access to `imaging_orders` is revoked; workflow RPCs are the mutation boundary.
- Imaging changes converge on the existing canonical clinical audit function.

## Safety and interoperability posture

DICOM/PACS identifiers are treated as reconciliation metadata. Transport acceptance does not itself create or finalize a clinical result. Clinical interpretation remains a human-controlled workflow.

The implementation deliberately does not introduce a second PACS, RIS, notification, or audit service. External transport can be integrated through the existing interoperability delivery ledger and device integration boundary.

## Verification

`test:nextgen-imaging-ris-pacs` is part of the architecture branch quality workflow and checks the migration, existing imaging lifecycle, canonical imaging foundation, duplicate protection, direct-write lockdown, and audit boundary.

Live migration replay remains dependent on the correct active Harmony Supabase project becoming available. Contract tests do not substitute for live RLS/database verification.
