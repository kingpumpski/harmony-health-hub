# Harmony Health Hub — Next-Generation HIMS Architecture Decision

## 1. Decision

Build the requested next-generation HIMS as an **isolated reference platform inside this feature branch**, rather than patching `main` directly or creating a disconnected repository. The branch is the architecture proving ground and migration target for the existing application.

The existing clinical application remains untouched by this work until an individual capability has passed its contract, security, clinical-safety, accessibility, integration, and quality gates.

The reference platform is organized around domain modules, shared platform services, a configuration plane, an interoperability plane, an event backbone, and explicit governance controls. Existing canonical tables and workflows remain authoritative during migration; no parallel production data model is introduced merely to satisfy a new UI.

## 2. Why this approach

The current application has a strong workflow foundation but is still organized primarily as a fertility-clinic HIMS. Its current architecture documents patient, clinical, fertility, laboratory, billing, reporting, follow-up, RBAC, Supabase/PostgreSQL and audit foundations. The current master reconciliation list already identifies 31 operational modules and requires UI, route, authorization, database, RLS, secure RPC, workflow state, audit, billing, notifications, integration, error handling and responsive behavior to agree before a module is considered complete.

The requested target is broader: multi-country HIMS, interoperability, device integration, accessibility, patient engagement, AI governance, data sovereignty, public health, population health, workforce, supply chain and enterprise security. Therefore the correct architectural move is a controlled reference platform that can prove the target boundaries before they are propagated into the production application.

## 3. Target architecture

### Experience plane
Role-aware web application, patient portal, mobile/PWA surfaces, accessibility services, localization, design system and offline interaction layer.

### Application/domain plane
Patient/EMPI, registration, appointments, encounters, clinical documentation, pharmacy, medication administration, laboratory, imaging, emergency, inpatient, nursing, theatre, anesthesia, maternity, fertility, dental, ophthalmology, telemedicine, referrals, care coordination, billing, claims, inventory, workforce, public health, reporting and patient engagement.

### Intelligence plane
AI orchestration, specialty assistants, clinical context assembly, retrieval/source registry, model registry, evaluation, safety policy, confidence thresholds, human approval, audit and incident management.

### Interoperability plane
FHIR resource services, HL7 v2 adapter, DICOM/PACS/RIS adapter, ASTM laboratory adapter, REST/Web services, bulk data exchange, terminology service, interface monitoring, message replay, reconciliation and dead-letter handling.

### Platform plane
Identity, RBAC/ABAC, tenant/facility isolation, consent, audit, notification, configuration, feature flags, file/document services, search, event bus, workflow engine, observability, backup/DR and data lifecycle controls.

### Data plane
Canonical transactional PostgreSQL data, longitudinal clinical record, terminology/reference data, event store, document/object storage, analytics/federated query layer and de-identified research datasets.

## 4. Non-negotiable architectural rules

1. Patient safety takes precedence over convenience.
2. Clinical AI is advisory; a licensed/authorized human remains accountable for clinical decisions.
3. Security controls are enforced server-side; frontend gating is supplementary.
4. Sensitive mutations use authoritative server workflows/RPCs with authorization, validation and audit.
5. Existing canonical data contracts are extended, not duplicated.
6. Every module has a declared state machine and ownership boundary.
7. Every cross-domain event is versioned and traceable.
8. Offline work is explicitly classified as safe-to-stage, conflict-sensitive, or prohibited.
9. PHI is excluded from ordinary telemetry, logs and analytics unless explicitly governed.
10. Jurisdictional policy is configuration, not scattered application logic.
11. Interoperability adapters are vendor-neutral and observable.
12. Accessibility is a release criterion, not a post-release enhancement.
13. No feature is declared production-ready solely because its route or UI exists.
14. Database migrations must be ordered, replayable and tested from a clean environment.
15. Main remains protected until the complete quality gate passes.

## 5. Migration strategy

Migration proceeds capability-by-capability:

1. Establish shared contracts and configuration.
2. Establish terminology, identity, consent and audit boundaries.
3. Establish interoperability and event contracts.
4. Implement domain capabilities behind feature flags.
5. Reconcile each capability against the existing canonical workflow.
6. Run security, accessibility, clinical-safety, performance and data-integrity validation.
7. Compare reference-platform behavior with current production behavior.
8. Promote only validated capabilities into the main application.

No wholesale rewrite is authorized. The reference platform exists to make the main application stronger, not to create an ungovernable second HIMS.

## 6. Definition of done

The branch is not mergeable until the implementation has:

- deterministic build, typecheck and lint success;
- unit, integration and end-to-end workflow coverage;
- database migration replay success from a clean environment;
- RLS and secure workflow verification;
- authorization-negative tests;
- accessibility testing at WCAG 2.2 AA baseline;
- offline synchronization and conflict tests;
- interoperability contract tests;
- device-message validation tests where adapters exist;
- AI safety and non-autonomy tests;
- PHI-safe observability verification;
- dependency and supply-chain review;
- performance/load checks against agreed budgets;
- disaster recovery and backup verification;
- clinical safety review for safety-relevant workflows;
- deployment verification on the actual target environment;
- traceability from requirement → module → workflow → data → permission → audit → test.

Only after these gates pass may a promotion PR to `main` be considered.