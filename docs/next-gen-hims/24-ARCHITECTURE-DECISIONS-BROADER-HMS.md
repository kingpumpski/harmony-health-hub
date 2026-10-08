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

## ADR-011 — Facility service availability is a hard activation boundary
Every optional or specialist module is disabled until the facility explicitly declares that it actually provides the represented service and is operationally ready. The facility module record carries service availability, readiness state, verification actor/time and notes. UI visibility is advisory; `hms_module_is_enabled` and `hms_assert_module_enabled` are authoritative. Explicit facility records override catalogue defaults.

## ADR-012 — Specialist roles use scoped assignments, not duplicated application identities
The 40-role tertiary-hospital target is implemented as specialized role assignments layered over the existing authenticated `app_role`. A user may hold a specialty role for a facility and department without creating a second authentication/RBAC system. Authorization evaluates both the compatibility app-role bridge and active facility-scoped specialist assignments.

## ADR-013 — Enterprise gaps are additive and service-gated
The assessment gaps for HR/payroll, ICU, mental health, social work, quality/compliance, infection prevention, mortuary, ambulance/transport, research, external audit and genomics are represented as canonical next-generation modules and governed data/workflow foundations. They do not replace existing clinical modules and remain unavailable at facilities that do not provide the corresponding service.


## ADR-014 — Enterprise workspaces use canonical governed read/write boundaries
New enterprise modules use a shared facility-scoped workspace contract and server-side command boundary. The UI does not receive unrestricted table mutation access. Each command verifies authentication, facility access, service availability, module state and role/specialist permissions before creating a record.

## ADR-015 — Patient self-service is an explicit authorization domain
Patient portal access is determined from the authenticated patient's linked identity (with a tightly scoped email fallback for legacy/unlinked records). Portal read functions return only that patient's records, while staff worklists retain their existing role/facility boundaries. Patient access must never be implemented by broadening staff permissions.

## ADR-016 — Module registry, manifest and platform catalogue must converge
The machine-readable module registry, executable module contracts and UI platform catalogue are release artifacts of the same architecture. A module is incomplete when any one of these surfaces is missing or inconsistent.
