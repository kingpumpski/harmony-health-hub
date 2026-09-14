# Diagnosis Import Acceptance Criteria

A diagnosis workbook is eligible for test import only when:

- every worksheet has been inspected;
- each worksheet has a stable header row;
- source standard/category/version are identifiable;
- required diagnosis fields are present;
- duplicate rows are classified rather than silently discarded;
- source codes are preserved;
- ICD-10 mappings are validated where supplied;
- unmapped diagnoses are explicitly reported;
- invalid records are excluded from the write set;
- the import is represented by an auditable batch;
- a dry-run produces zero schema/constraint errors;
- post-import counts reconcile with the approved write set.

The assessment must not mutate diagnosis tables. The actual import should be a separate explicit operation after review.
