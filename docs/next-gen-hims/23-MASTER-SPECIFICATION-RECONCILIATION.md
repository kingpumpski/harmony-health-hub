# Master HMS Specification Reconciliation

## Canonical decision
Harmony Health Hub remains the single canonical HMS/HIMS. The broader HMS prompt is absorbed into the existing next-generation architecture; no second application, backend, database, or parallel clinical record is created.

## Coverage already present
The canonical platform already covers patient registration/EMPI, appointments, encounters/EMR, pharmacy/MAR, laboratory, imaging/RIS-PACS, emergency, admissions/wards/beds, nursing, theatre/anesthesia, maternity, fertility, dental, ophthalmology, telemedicine, billing, claims, inventory, workforce, reports/public health, patient portal/messaging/notifications, interoperability, device integration, AI governance, accessibility, audit, configuration and offline continuity.

## Broader prompt gaps and actions

| Requirement | Current state | Action |
|---|---|---|
| Physiotherapy | No dedicated workflow | Add module contract and facility gate; reuse encounters/care plans |
| Dietary/restaurant | Canteen/meal workflow exists | Reframe as Dietary & Nutrition; retain existing canonical tables |
| Teaching & research | Not governed as a module | Add isolated secondary-use boundary |
| Data Import Engine | Bulk upload exists | Add versioned templates, staging, validation, quarantine, approval, commit, rollback and audit |
| Report Centre | Reports/submissions exist | Consolidate as governed Report Centre |
| Asset & Biomedical | Missing | Add equipment/maintenance lifecycle boundary |
| Procurement | Inventory exists | Add supplier/PO/receiving/reconciliation boundary |
| User & Role Management | RBAC exists but role catalogue is narrow | Add enterprise role catalogue and module permission matrix |
| Facility Module Manager | Browser flags exist | Add server-authoritative facility/module configuration |
| OpenAPI/API-first | Supabase REST/RPC is the API boundary | Document canonical REST/RPC contracts; do not add a redundant API server |
| Security/MFA/OIDC | Auth/RLS foundation exists | Preserve provider architecture and validate deployed controls separately |

## Merged architecture
**Presentation → Auth/RBAC + Facility Module Gate → Canonical Application Workflows → PostgreSQL/Supabase → Integration/Interoperability Boundary**

Cross-cutting controls apply to every layer: facility/module eligibility, least privilege, clinical/financial safety, audit, idempotency, concurrency, consent, offline staging/replay, interoperability provenance and configuration change control.

The system remains a modular monolith. New infrastructure is introduced only where measured requirements require it.

## Strategic goals
1. Provide one configurable HMS/HIMS for regional, specialist and teaching facilities.
2. Preserve and strengthen the canonical clinical record.
3. Make optional capabilities configuration-driven and server-authoritative.
4. Establish reversible, auditable data migration/import.
5. Establish a governed Report Centre.
6. Expand enterprise operations into procurement, biomedical assets, dietary services and teaching/research without creating parallel clinical truth.
7. Expand role governance to the organizational operating model.
8. Scale FHIR, HL7, DICOM, ASTM and governed REST/SOAP interoperability.
9. Keep AI advisory-only with human review.
10. Support resilient/offline operations without bypassing server authorization.
11. Prepare for multi-facility, jurisdiction-aware deployment.
12. Reach development completeness before formal validation and deployment certification.

## Revised objectives
- Disabled facility modules deny access regardless of RBAC role.
- Imports are staged and reversible; uploaded files never write directly to clinical truth.
- Reports retain generation and submission provenance.
- Teaching/research defaults to de-identified or explicitly authorized data.
- Biomedical assets are operational assets; clinical device integration remains a separate safety boundary.
- Procurement receiving reconciles to inventory without silently creating stock.
- Every write path converges on canonical audit/workflow boundaries.
- No new module may introduce a second patient, billing, notification, audit or identity source of truth.

## Completion model
Development completeness is distinct from production readiness. Development complete means required workflows, boundaries, configuration, contracts, tests and documentation exist. Production ready additionally requires exact-head CI, migration replay, RLS/security, accessibility, interoperability, performance/resilience, clinical safety, deployment and UAT evidence.
