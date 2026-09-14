# Diagnosis Workbook Import Workflow

## Purpose

Harmony Health Hub supports controlled import of multi-sheet Excel workbooks for clinical reference data. Diagnosis workbooks must be assessed and validated before any database mutation.

## Required workflow

1. Upload the `.xlsx` workbook to the repository under `data/diagnosis/` for assessment.
2. Inspect every worksheet, not only the first worksheet.
3. Normalize headers and blank values without altering source terminology.
4. Produce a dry-run report containing worksheet names, row counts, columns, duplicates, missing required fields, malformed codes, and unmapped ICD-10 values.
5. Resolve structural/schema errors before import.
6. Create an auditable import batch.
7. Import only validated rows inside the approved diagnosis-standard model.
8. Record rejected rows and reasons; never silently discard data.
9. Verify row counts and referential integrity after import.

## Diagnosis model

- `diagnosis_standards`: identifies each source/standard and version.
- `stg_diagnoses`: stores Ghana STG diagnosis records.
- `diagnosis_standard_mappings`: stores mappings between a source diagnosis and ICD-10 or other standards.
- `facility_diagnosis_standards`: controls which standard/version is active for a facility.

## Safety rules

- The assessment stage must be read-only against the database.
- A workbook containing multiple sheets must never be reduced to its first sheet by the importer.
- Import must be idempotent and batch-auditable.
- Do not fabricate ICD-10 mappings. Unmapped records remain explicitly reviewable.
- Preserve source category, source terminology, source code, and version information.
- Production import requires explicit administrative action after a successful dry run.
