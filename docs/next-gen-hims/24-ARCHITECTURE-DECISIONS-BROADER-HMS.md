# Architecture Decisions — Broader HMS Scope

## ADR-001 — Harmony Health Hub remains canonical
The broader specification extends the existing HIMS. Existing patient, encounter, billing, audit, notification and integration boundaries remain canonical.

## ADR-002 — Modular monolith remains primary
React/Vite + Supabase/PostgreSQL remains the implementation stack. A separate NestJS/Spring/Django API is not introduced merely to satisfy a generic reference stack. Supabase REST/RPC/Edge Functions are the API boundary.

## ADR-003 — Facility modules are server-authoritative
Browser storage is for presentation preferences only. Production module enablement is persisted per facility and checked by secure workflows/RLS. A disabled module denies access even when RBAC would otherwise permit it.

## ADR-004 — Import is isolated from clinical truth
Files enter staging/quarantine. Validation, approval and atomic commit are explicit workflow boundaries. Rejected data cannot partially mutate canonical clinical tables.

## ADR-005 — Report Centre reuses existing reporting
Reports Center and report-submission surfaces remain canonical. New metadata/run/submission tables provide governance; a parallel reporting application is prohibited.

## ADR-006 — Biomedical assets differ from clinical device integration
Biomedical assets cover ownership, location, service, calibration, maintenance and lifecycle. Clinical device integration covers transport/protocol/result provenance. Transport cannot manufacture clinical truth.

## ADR-007 — Teaching/research is segregated
Teaching/research is a secondary-use workload. Production patient data is not exposed by default. Approved datasets carry purpose, approver, retention and de-identification/provenance metadata.

## ADR-008 — Enterprise roles are additive
The existing app_role authorization model remains intact. A broader role catalogue is configuration metadata; new role enforcement must be added through explicit policies/workflows before production enablement.

## ADR-009 — OpenAPI is a contract
The project documents its existing REST/RPC boundary using OpenAPI-compatible contracts. A new backend service is introduced only if measured scale requires it.

## ADR-010 — AI remains advisory
No assistant may autonomously create, approve, finalize, dispense, administer, adjudicate or otherwise commit clinical truth.
