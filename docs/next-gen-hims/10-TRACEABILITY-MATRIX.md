# Next-Generation HIMS Traceability Matrix

This matrix converts the consolidated HIMS brief into implementation obligations. A deliverable is not complete until its code, database/workflow dependencies, authorization model, audit path, tests, and deployment evidence are traceable.

| Deliverable domain | Reference implementation | Validation evidence required | Status |
|---|---|---|---|
| Vision and scope | `00-ARCHITECTURE-DECISION.md` | architecture review | defined |
| Layered architecture | architecture decision + module contract | dependency/reconciliation review | defined |
| Configurability | `02-CONFIGURATION-AND-DATA-SOVEREIGNTY.md`, platform deployment profile | migration replay + policy review | foundation |
| EMPI / patient identity | existing patient workflow + module contract | identity duplicate/merge tests | existing + reconcile |
| Clinical record / encounters | existing encounters and records workflows | clinical workflow tests | existing + reconcile |
| Pharmacy / medication | existing pharmacy and medication administration | medication safety tests | existing + reconcile |
| LIS | existing laboratory workflow + interoperability boundary | specimen/result/device fixtures | existing + expand |
| RIS/PACS | existing imaging workflow + DICOM boundary | DICOM routing fixtures | existing + expand |
| Billing / claims | existing billing and claims workflows | financial invariant tests | existing + reconcile |
| Inventory / supply chain | existing inventory workflow | stock/lot/expiry tests | existing + expand |
| Workforce | existing roster/shift foundations | scheduling conflict tests | existing + expand |
| Public health | reporting foundations | de-identification/reporting tests | expand |
| Device integration | `03-INTEROPERABILITY-AND-DEVICE-INTEGRATION.md`, device registry migration | adapter contract + replay tests | foundation |
| Interoperability | same + endpoint/event registries | FHIR/HL7/DICOM/ASTM fixtures | foundation |
| AI clinical hub | existing AI clinical hub + `04-AI-SAFETY-AND-GOVERNANCE.md` | safety/red-team/HITL evidence | existing + expand |
| AI governance | AI model registry/evaluation migration | approval and lifecycle tests | foundation |
| Accessibility | `05-ACCESSIBILITY-AND-PATIENT-ENGAGEMENT.md`, runtime preferences | keyboard/screen-reader/contrast/zoom tests | foundation |
| Patient engagement | existing portal/chat/notifications + communication preferences | consent/channel tests | existing + expand |
| Security/privacy | `06-SECURITY-PRIVACY-COMPLIANCE.md` | RLS, auth, audit, threat tests | foundation + reconcile |
| Localization/data residency | deployment profiles | country-profile and residency tests | foundation |
| Standards | `07-STANDARDS-MATRIX.md` | implementation-to-standard mapping | defined |
| Roadmap | `08-IMPLEMENTATION-ROADMAP.md` | phase exit criteria | defined |
| Quality gates | `09-QUALITY-GATE.md` | fresh exact-commit evidence | active |

## Promotion rule

`foundation` means the architecture and enabling primitives exist. `existing + reconcile` means the current application already provides material capability and must be strengthened without duplicating canonical workflows. `expand` means missing functionality remains an implementation workstream. No status is promoted to production-ready without the quality gate evidence for that domain.

## Non-negotiable traceability

Every safety-critical operation must be traceable to an authenticated actor, authorization decision, domain workflow, durable record, audit event, and failure/recovery path. AI-assisted actions additionally require model/version provenance, source policy, uncertainty handling, human review where required, and an auditable final decision.
