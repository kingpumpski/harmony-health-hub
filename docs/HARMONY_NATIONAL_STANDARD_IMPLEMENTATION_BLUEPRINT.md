# Harmony Health Hub — National-Standard HMS Implementation Blueprint

**Status:** Architecture / implementation roadmap  
**Repository:** `kingpumpski/harmony-health-hub`  
**Target:** Ghana-first, multi-facility, configurable HIMS/HMS with incremental expansion  
**Implementation rule:** Extend the existing Harmony canonical architecture. Do not create parallel patient, encounter, billing, pharmacy, notification, role, or reporting systems.

---

## 1. Executive direction

The supplied national-standard HMS specification is a useful **target-state capability catalogue**, but it should not be copied literally into Harmony.

Harmony already has substantial foundations for:

- patient registration and Patient Hub
- appointments and encounter launch
- encounters, clerking, diagnoses and prescriptions
- triage/vitals and BMI context
- laboratory workflows
- radiology/imaging workflows
- pharmacy, dispensing and inventory
- medication administration
- billing/accounts and insurance claims
- admissions, wards/beds and care transitions
- nursing handover/care plans
- emergency, theatre, anesthesia, transfusion and maternity
- fertility, dental, ophthalmology and procedure notes
- telemedicine foundations
- AI Clinical Hub with advisory-only safeguards
- notifications and workflow attention
- facility-scoped authorization/RLS
- audit/security contracts
- Reports Center foundation
- administrative/user/system-library workflows

The implementation strategy therefore changes from **"build a new HMS"** to:

> **Reconcile → strengthen → connect → expand → certify each existing capability before introducing the next capability.**

The supplied 40-role model is also treated as a **business-role catalogue**, not as 40 PostgreSQL enum values. Harmony should use a stable role/permission model with department, facility, assignment and data-scope attributes. This avoids an unmaintainable enum explosion and allows future hospitals to configure roles without changing the database type for every new job title.

---

# 2. Architecture decisions

## 2.1 Keep the current application architecture

### Current baseline

- React + TypeScript + Vite
- Tailwind CSS + shadcn/Radix UI
- Recharts
- Supabase Auth/Postgres/Realtime/Edge Functions/Storage
- PostgreSQL as the canonical transactional database
- Row-level security and server-authoritative RPC workflows
- GitHub Actions quality/security contracts
- GitHub Pages as the current test deployment target
- Vercel deferred

### Do not introduce yet

Do **not** replace the current stack with NestJS/FastAPI, MongoDB, TimescaleDB, Kafka, RabbitMQ, Redis or Kubernetes merely because they appear in the supplied prompt.

Those technologies are optional scale-out components, not prerequisites for the HMS capabilities.

Adopt them only when an evidence-based workload, integration, operational requirement or deployment constraint justifies them.

### Preferred evolution

1. PostgreSQL remains the system of record.
2. Supabase Realtime handles current live UI updates.
3. Workflow events are represented by durable database records/outbox patterns.
4. Notification routing remains server-authoritative and role/facility scoped.
5. Edge Functions handle external integrations and asynchronous work where appropriate.
6. A dedicated broker can be introduced later without changing business event contracts.
7. FHIR/HL7/DICOM adapters sit at an interoperability boundary rather than leaking vendor-specific structures into core tables.

---

# 3. Non-negotiable architectural rules

Every module must satisfy these rules before being considered complete.

### Security

- Facility boundary is enforced server-side.
- Test-mode users remain restricted to the designated test facility.
- RLS is enabled on exposed user-data tables.
- Protected mutations use authorized RPCs or Edge Functions.
- SECURITY DEFINER is used only where justified and with explicit authorization.
- No service-role/secret key reaches the browser.
- Authorization never depends on editable user metadata.
- Admin/IT Admin troubleshooting access does not bypass facility boundaries unless an explicit server-authorized support operation exists.
- Sensitive clinical data is not broadcast through broad Realtime subscriptions.

### Clinical safety

- AI is advisory and never autonomously diagnoses, prescribes, doses, or closes a clinical workflow.
- Critical clinical alerts require acknowledgement/escalation state.
- Clinical reference values are configurable rather than hardcoded.
- Every clinical decision-support output carries provenance and freshness information.
- Signed/locked clinical records are immutable or versioned according to policy.

### Data integrity

- One canonical patient identity.
- One canonical encounter.
- One canonical bill/order lineage.
- One canonical medication catalogue and facility stock model.
- One canonical notification/workflow-attention model.
- One canonical reporting definition library.
- No duplicate tables introduced to imitate an existing domain.

### Operational UX

Every operational module must include:

- role-scoped dashboard
- worklist
- create/action flow
- loading state
- empty state
- error state
- mobile/small-screen behavior
- search/filter where operationally necessary
- audit visibility where appropriate
- actionable notifications
- clear patient/facility context
- minimal dashboard clutter

---

# 4. Target authorization model

Instead of implementing the supplied 40 roles as a flat enum, Harmony should model:

**User → Role Assignment → Facility → Department/Unit → Job Function → Permission Set → Data Scope**

Recommended scopes:

- system
- organization
- facility
- department
- ward/unit
- assigned patient
- encounter
- own work queue
- aggregate/de-identified
- external audit

The supplied roles become configurable role profiles such as:

### Executive/governance
- Super Admin
- Hospital Director/CEO
- Medical Director
- Compliance/Legal
- Quality Assurance
- Infection Control
- Public Health
- External Auditor

### Clinical
- Consultant/Specialist
- Resident/House Officer
- Nurse
- Triage Nurse
- Emergency Physician
- Surgeon
- Anesthesiologist
- ICU Intensivist
- Dietitian
- Physiotherapist/OT/Speech
- Psychologist/Psychiatrist
- Social Worker
- etc.

### Diagnostic/ancillary
- Pharmacist
- Lab Scientist/Pathologist
- Radiologist/Imaging Technician
- Blood Bank Officer
- Biomedical Engineer

### Operations/non-clinical
- Front Desk
- Admissions
- Ward Clerk
- HIM/Medical Records
- Billing/Finance
- Claims
- HR
- Payroll
- Supply Chain
- IT/Security
- Kitchen/Dietary
- Mortuary
- Ambulance/Paramedic

### Patient/research
- Patient/Caregiver
- IRB-approved Researcher

A single user may hold multiple assignments where the server permits it.

---

# 5. Event architecture

The target event model is:

**Domain action → durable event → routing rule → affected recipient(s) → dashboard/worklist → acknowledgement/escalation → audit**

Examples:

- `appointment.booked`
- `encounter.opened`
- `encounter.closed`
- `lab.resulted`
- `lab.critical`
- `imaging.reported`
- `prescription.created`
- `rx.verified`
- `rx.dispensed`
- `rx.administered`
- `bed.assigned`
- `patient.transferred`
- `invoice.generated`
- `claim.denied`
- `report.overdue`
- `incident.reported`

Each event must contain, where applicable:

- event ID
- event type
- actor
- facility
- department/unit
- patient reference
- encounter reference
- source entity
- occurred_at
- severity
- correlation ID
- idempotency key
- payload version

The event payload must not contain unnecessary PHI.

## Notification tiers

### Info
Routine workflow attention.

### Warning
Action required but not immediately dangerous.

### Critical
Immediate clinical/operational attention with acknowledgement and escalation rules.

Critical notifications must not rely on sound alone. Sound is an accessibility enhancement, not the only alert channel.

---

# 6. Reporting Center strategy

Harmony already has a Reports Center foundation with facility-aware report definitions, configurations, generation runs, generation items and submissions.

Therefore the Reporting Center is **not a new Phase-5-from-zero project**.

It should evolve through:

1. definition validation
2. extractor implementation
3. encounter/reporting data mapping
4. validation rules
5. generation
6. approval/signature
7. submission adapters
8. retry/failure handling
9. immutable archive
10. statutory evidence/audit

### Ghana-first rule

The first statutory reporting layer should prioritize verified Ghana requirements and official facility/program metadata.

Do not label a report as legally required merely because it appears in a generic international HMS prompt.

Each report definition must record:

- jurisdiction
- authority
- official source/reference
- reporting frequency
- effective date/version
- facility applicability
- required data elements
- validation rules
- submission method
- approval/signature requirement
- retention requirement
- implementation status

Automatic submission must remain disabled until the connector, authorization, format and destination are explicitly configured and tested.

---

# 7. Phase-by-phase implementation plan

## PHASE 0 — Foundation Reconciliation and Platform Governance

### Objective

Make the existing platform a stable foundation rather than rebuilding scaffolding.

### Features

1. Authentication/session hardening
2. Role/permission architecture
3. Facility and department context
4. Test-mode governance
5. Design system
6. Audit architecture
7. Notification/event architecture
8. Global search
9. configuration/reference-data architecture
10. migration and deployment governance

### Deliverables

- canonical permission matrix
- configurable role profiles
- facility/department assignment model
- active context enforcement
- audit event taxonomy
- event envelope contract
- notification routing contract
- accessible design tokens
- dark/light mode
- sound abstraction that never creates an AudioContext before user interaction
- architecture documentation
- security contracts

### Exit gate

No known direct-write authorization bypasses, no uncontrolled cross-facility reads, and all core foundation contracts pass.

---

# PHASE 1 — Core Patient Journey

## 1A Patient / MPI

Strengthen:

- registration
- MRN/hospital ID
- duplicate detection
- demographic quality
- consent
- next-of-kin
- identifier provenance
- patient merge/unmerge governance
- patient timeline

Events:

`patient.created`, `patient.updated`, `patient.merged`

### Exit gate

Registration → patient hub → appointment → encounter works without facility or identity ambiguity.

## 1B Appointments

Strengthen:

- provider/resource scheduling
- active appointment worklists
- queue
- reminders
- cancellation/no-show
- appointment → encounter continuity

Events:

`appointment.booked`, `appointment.reminder`, `appointment.no_show`

## 1C Encounters

Treat Encounter as the backbone.

Required:

- outpatient
- inpatient
- emergency
- day procedure
- telemedicine
- home-care
- ICU/OR extension

Every encounter should connect:

patient → provider → facility → location → reason → diagnosis → orders → notes → vitals → disposition → billing lineage → reporting lineage.

Events:

`encounter.opened`, `encounter.updated`, `encounter.closed`

## 1D Clinical documentation

Strengthen:

- clerking/H&P
- SOAP/progress
- consultation
- procedure notes
- discharge summary
- signatures
- version history
- locked records

## 1E Vitals and flowsheets

Build from existing triage/BMI work.

Add progressively:

- configurable vital sets
- trends
- abnormal thresholds
- early warning scores
- care-area-specific flowsheets
- escalation

No hardcoded Ghana clinical ranges.

---

# PHASE 2 — Diagnostics

## 2A Laboratory

Existing laboratory infrastructure is retained.

Complete:

- order
- specimen
- accession
- worklist
- result
- validation
- approval
- critical result routing
- cumulative patient results
- reference values
- analyzer integration boundary

Critical result flow:

**result validated → criticality evaluated → ordering clinician/assigned nurse → acknowledgement → escalation → audit**

## 2B Radiology

Complete:

- order
- scheduling
- modality worklist
- report
- critical findings
- report acknowledgement
- DICOM/PACS adapter boundary

DICOM/PACS integration should be introduced through an adapter, not embedded into every clinical component.

## 2C Blood Bank

Introduce after core diagnostic contracts are stable:

- donor/component records
- inventory
- compatibility/crossmatch
- issue
- transfusion
- reaction
- traceability
- reporting

---

# PHASE 3 — Medication, Pharmacy and Inpatient Operations

## 3A Pharmacy

Existing pharmacy and inventory foundations should be reconciled rather than replaced.

Complete:

- prescription verification
- clinical safety review
- dispensing
- substitutions
- inventory
- expiry/FEFO
- controlled medicines
- returns
- patient counselling
- adverse drug reaction workflow
- medication administration integration

## 3B Medication Administration

Complete:

- scheduled doses
- administration record
- omissions
- reasons
- barcode/device integration boundary
- shift-aware notifications
- adverse-event linkage

## 3C Ward and Beds

Complete:

- bed board
- admission
- transfer
- discharge
- isolation
- housekeeping state
- capacity
- discharge planning

Core transition:

**admission → bed → care team → nursing → clinical encounter → billing → discharge → follow-up**

## 3D Nursing handover and care plans

Complete:

- handover
- acknowledgement
- care plan
- assigned/on-duty staff
- escalations
- continuity across shifts

---

# PHASE 4 — Procedural and Acute Care

## 4A Emergency

Complete:

- emergency case
- acuity
- queue
- trauma activation
- emergency encounter
- admission/transfer
- critical alerts

## 4B Theatre

Complete:

- scheduling
- checklist
- pre-op
- intra-op
- specimen
- implant
- post-op
- billing capture

## 4C Anesthesia

Complete:

- pre-op assessment
- anesthesia record
- intra-op events
- PACU
- clearance linkage

## 4D ICU/Critical Care

Introduce only after the encounter, medication, vitals and event contracts are stable.

Capabilities:

- ICU admission
- severity scoring
- flowsheets
- ventilator data boundary
- infusions
- sedation/delirium
- critical events
- family-update documentation
- discharge criteria

---

# PHASE 5 — Revenue Cycle and Enterprise Operations

## 5A Billing and Revenue Cycle

Strengthen existing billing:

- charge capture
- tariffs
- packages
- invoice
- payment
- deposit/credit
- refund
- receipt
- ageing
- financial audit

Every charge must have source lineage.

## 5B Insurance and Claims

Complete:

- payer
- eligibility
- preauthorization
- claim
- submission
- remittance
- denial
- appeal
- reconciliation

Claims must remain linked to encounter/order/service source data.

## 5C HR and Staff Operations

Introduce:

- staff profile
- credentials
- departments
- shifts
- leave
- attendance
- training
- credential expiry
- roster

Payroll should be a separate controlled financial submodule, not mixed into clinical data.

## 5D Supply Chain

Extend pharmacy inventory architecture to enterprise inventory:

- suppliers
- procurement
- PO
- GRN
- stores
- requisition
- batch/expiry
- FEFO
- asset linkage
- wastage

---

# PHASE 6 — Governance, Reporting and Regulatory Operations

## 6A Reporting Center

Promote the existing Reports Center foundation into a production workflow.

### Pipeline

**Encounter/event → reporting data mart/read model → report definition → validation → review → signature → submission → response → archive**

Support:

- weekly
- monthly
- quarterly
- annual
- ad-hoc

### Submission channels

Add only where configured:

- API
- secure file transfer
- approved email gateway
- manual export
- HL7/FHIR

Every submission needs:

- immutable report snapshot
- submission actor
- destination
- timestamp
- status
- response/reference
- retry history

## 6B Quality and Accreditation

- KPI library
- audit programme
- incidents
- RCA
- PDSA
- corrective actions
- accreditation evidence

## 6C Infection Prevention and Control

- HAI
- isolation
- outbreak
- exposure
- hand hygiene
- sterilization
- antimicrobial stewardship

## 6D Public Health

- notifiable cases
- case investigation
- surveillance
- outbreak
- contact tracing
- public-health reporting

## 6E HIM / Compliance / Legal

- chart completion
- coding
- ROI
- consent
- legal hold
- retention
- de-identification
- audit review

---

# PHASE 7 — Patient and Connected Care

## 7A Patient Portal

Use the existing patient identity model.

Add:

- appointments
- results
- prescriptions
- bills
- care plans
- secure messaging
- education
- consent
- caregiver/proxy access

Patient access must remain strictly own-record scoped.

## 7B Telemedicine

Extend existing telemedicine lifecycle.

Add:

- secure waiting room
- video provider
- encounter linkage
- documentation
- billing
- consent
- connectivity fallback

Recording is opt-in and consent-controlled.

## 7C Mobile

Only after web workflows are stable.

Staff app:

- critical alerts
- rounds
- approvals
- medication administration
- results

Patient app:

- portal functions
- appointments
- results
- messages

Offline operation must use an explicit security model and reconciliation queue.

---

# PHASE 8 — Specialty Care

Implement specialty modules using a common extension framework.

Priority groups:

1. Oncology
2. Cardiology
3. Renal/Dialysis
4. Obstetrics/Neonatal
5. Pediatrics
6. Neurology/Stroke
7. Mental Health
8. Rehabilitation
9. Dietetics
10. Mortuary
11. Palliative/Hospice
12. Other specialties

Each specialty gets:

- specialty episode
- structured clinical data
- specialty worklist
- documentation
- orders
- notifications
- billing linkage
- reporting linkage
- audit

Do not create a completely separate patient or encounter model per specialty.

---

# PHASE 9 — Interoperability

Create an explicit interoperability layer.

## FHIR

Start with:

- Patient
- Encounter
- Practitioner
- Organization
- Observation
- Condition
- Procedure
- DiagnosticReport
- ServiceRequest
- MedicationRequest
- MedicationDispense
- MedicationAdministration
- AllergyIntolerance
- Appointment
- CarePlan
- Coverage
- Claim

## HL7 v2

Prioritize:

- ADT
- ORM
- ORU

## DICOM

Prioritize:

- modality worklist
- study metadata
- report linkage
- PACS/viewer integration

## Integration controls

- mapping
- validation
- retries
- idempotency
- dead-letter handling
- connection monitoring
- audit

---

# PHASE 10 — Analytics, AI, Research and Scale

## 10A BI

Build a reporting/analytics read model before introducing a separate warehouse.

Metrics:

- occupancy
- ALOS
- mortality
- readmission
- throughput
- revenue
- claims denial
- patient satisfaction
- diagnostic turnaround
- pharmacy utilization
- staffing

Financial and clinical datasets must remain appropriately separated.

## 10B AI

AI capabilities must be introduced as **assistive decision support**:

- triage assistance
- deterioration detection
- sepsis risk
- readmission risk
- demand forecasting
- no-show risk
- anomaly detection
- imaging assistance
- medication interaction assistance

Every AI output must contain:

- model/version
- source data
- timestamp
- confidence
- explanation/provenance
- clinician action
- override capability

No autonomous prescribing, diagnosis or treatment execution.

## 10C Genomics

- genomic observations
- variants
- pharmacogenomics
- hereditary risk
- oncology molecular data
- consent
- research export

## 10D Research

- IRB study registry
- cohort builder
- de-identification
- data request approval
- controlled export
- research audit

---

# PHASE 11 — Security, Resilience, Observability and Go-Live

## Security

- application security review
- authorization regression
- RLS review
- dependency review
- secrets management
- rate limiting
- WAF/integration controls
- incident response
- audit evidence

## Disaster recovery

Define:

- RPO
- RTO
- backup schedule
- restore test
- DR drill
- business continuity plan

## Observability

Introduce progressively:

- structured logs
- application metrics
- database metrics
- tracing
- workflow latency
- queue depth
- notification delivery
- integration health

Prometheus/Grafana/OpenTelemetry are candidates at this stage, not Phase 0 prerequisites.

## Go-live

- training
- super-user programme
- operational manuals
- role-specific guides
- change management
- pilot facility
- staged rollout
- hypercare
- incident/change feedback loop

---

# 8. Dashboard architecture

The supplied color palette should become a **theme token catalogue**, not hardcoded page-by-page colors.

Recommended semantic tokens:

- clinical
- emergency
- pharmacy
- laboratory
- finance
- administration
- patient
- critical
- warning
- success
- neutral

Accessibility requirements:

- WCAG 2.2 AA target
- color never carries meaning alone
- keyboard navigation
- visible focus
- screen-reader labels
- reduced motion support
- adequate contrast
- non-audio critical alert fallback

The dashboard principle is:

> **Operational information first; analytics second.**

Each role should see only the work required for that role, with cross-module information appearing as relevant workflow context rather than unrelated navigation.

---

# 9. Communication model

The supplied communication matrix is retained conceptually but implemented through controlled workflow channels.

### Direct workflow message

Actor → named recipient.

### Role attention

Event → authorized role(s).

### Department attention

Event → authorized department queue.

### Facility broadcast

Reserved for authorized administrators and operational emergencies.

### Handover

Sending team → receiving team → acknowledgement.

### Critical escalation

Example:

**critical lab result → ordering clinician → assigned nurse → on-call clinician**

The five-minute escalation target is a configurable policy, not a hardcoded universal assumption.

---

# 10. Module completion contract

A module is not complete because its page exists.

Every module must pass:

1. Database/schema
2. Migration replayability
3. RLS
4. RPC/API authorization
5. Role matrix
6. Facility boundary
7. UI
8. Responsive behavior
9. Loading/empty/error states
10. Audit
11. Notifications/events
12. Billing/payment where applicable
13. Cross-module integration
14. Idempotency/concurrency
15. Test contracts
16. Build/typecheck/lint
17. Live verification where applicable
18. Documentation
19. Security review
20. User acceptance

Only then can the next module begin.

---

# 11. Implementation order inside each feature

Every feature should be implemented in this order:

### Step 1 — Existing capability audit
Find existing tables, migrations, RPCs, routes, components and tests.

### Step 2 — Gap analysis
Classify:

- already complete
- partially complete
- insecure
- disconnected
- UI-only
- backend-only
- duplicate
- missing

### Step 3 — Data contract
Define or reconcile canonical tables and relationships.

### Step 4 — Security contract
Define roles, facility scope, department scope and permitted actions.

### Step 5 — Server workflow
Implement protected RPC/Edge Function workflow.

### Step 6 — Event contract
Emit durable event/notification only after the authoritative transaction succeeds.

### Step 7 — UI
Build the operational workspace around the server workflow.

### Step 8 — Integration
Connect upstream/downstream modules.

### Step 9 — Tests
Add regression contracts before declaring completion.

### Step 10 — Verification
Run repository quality checks and, where available, live/browser verification.

### Step 11 — Documentation
Update the canonical reconciliation list and module documentation.

---

# 12. What is adopted from the supplied specification

## Adopt now

- module-by-module implementation
- role-scoped dashboards
- facility/department-aware permissions
- event-driven workflow attention
- clinical encounter backbone
- configurable reporting center
- advanced care extension model
- FHIR/HL7/DICOM interoperability
- accessibility
- auditability
- patient portal
- telemedicine
- quality/IPC/public-health governance
- specialty modules
- AI with clinician override
- research/de-identification
- disaster recovery
- observability
- training/go-live controls

## Modify before adoption

### 40 roles
Convert to configurable role profiles instead of a fixed enum.

### Kafka/RabbitMQ/Redis
Use only when scale or integration requirements justify them. Start with PostgreSQL/Supabase durable events + Realtime.

### MongoDB/TimescaleDB
Do not duplicate the transactional model. Introduce specialized stores only after a demonstrated workload requires them.

### NestJS/FastAPI
Not required for the current application. Edge Functions and PostgreSQL workflows remain the initial service boundary.

### Framer Motion
Use selectively. Accessibility/reduced-motion support takes precedence over animation.

### Sound
Use only as secondary feedback. Never create an AudioContext before a user gesture.

### HIPAA
Treat HIPAA as an international design reference where useful, but Ghana's applicable law, regulatory obligations, contracts and facility policies govern the deployment.

### Automatic statutory submission
Never enable by assumption. It requires verified authority, format, connector, credentials, approval and test evidence.

---

# 13. Current Harmony capability mapping

| Target capability | Existing Harmony position | Strategy |
|---|---|---|
| Auth/RBAC | Strong foundation | Reconcile/configure |
| Facility isolation | Strong and actively hardened | Preserve and expand |
| Patient/MPI | Existing | Strengthen |
| Appointments | Existing | Complete integration |
| Encounters | Existing, actively hardened | Make backbone |
| Clerking/notes | Existing and being refined | Complete |
| Vitals/BMI | Existing | Expand to flowsheets |
| Laboratory | Existing | Complete LIS lifecycle |
| Radiology | Existing | Complete interoperability boundary |
| Pharmacy | Existing, substantially implemented | Reconcile/complete |
| Medication administration | Existing | Complete |
| Billing | Existing | Complete revenue-cycle lineage |
| Insurance | Existing | Complete |
| Admissions/beds | Existing | Complete ADT |
| Nursing handover | Existing | Complete |
| Emergency | Existing | Complete |
| Theatre/anesthesia | Existing | Complete |
| Transfusion | Existing | Complete |
| Maternity/fertility/dental/ophthalmology | Existing | Specialty reconciliation |
| Telemedicine | Existing foundation | Complete |
| Notifications | Existing | Convert to durable event architecture |
| Reports Center | Existing foundation | Build statutory execution layer |
| QA/IPC/Public Health | Partial/future | Phase 6 |
| Patient Portal | Existing/foundation | Phase 7 |
| Mobile | Future | Phase 7 |
| Advanced specialties | Partial/future | Phase 8 |
| FHIR/HL7/DICOM | Partial/foundation | Phase 9 |
| BI | Partial/future | Phase 10 |
| AI | Existing advisory foundation | Expand safely |
| Genomics | Future | Phase 10 |
| Research | Future | Phase 10 |
| Security/DR/observability | Strong security contracts; operational maturity ongoing | Phase 11 |

---

# 14. Immediate implementation sequence for Harmony

The next implementation sequence should **not** start with a new giant Phase 0 rebuild.

It should be:

### Gate A — Current Encounter/Patient Hub stabilization
- finish PR #273 validation
- resolve remaining patient-selection/runtime issues
- verify appointment → encounter → patient context
- verify clerking → diagnosis → orders → prescription continuity

### Gate B — Foundation reconciliation
- permissions/role catalog
- active facility context
- notification/event contract
- audit coverage
- dashboard/navigation contract
- reference-value configuration

### Gate C — Core clinical completion
- encounters
- clinical notes
- vitals/flowsheets
- laboratory
- radiology
- pharmacy
- medication administration

### Gate D — ADT and inpatient
- admissions
- wards/beds
- transfers
- handover
- discharge

### Gate E — Revenue and enterprise
- billing
- insurance
- inventory
- staff/shift operations

### Gate F — Reporting/governance
- Reports Center
- QA
- IPC
- Public Health
- HIM/compliance

### Gate G — Connected care
- patient portal
- telemedicine
- mobile

### Gate H — Advanced care and interoperability
- specialties
- FHIR
- HL7
- DICOM

### Gate I — AI/analytics/research
- BI
- predictive/assistive AI
- genomics
- research

### Gate J — Resilience and go-live
- security
- DR
- observability
- training
- phased rollout

---

# 15. Definition of "production-ready"

Harmony should not use the phrase "production-ready" merely because a page works.

A module reaches production readiness only when:

- its data model is canonical
- its security model is tested
- its facility boundary is tested
- its mutation path is server-authoritative
- its audit trail is complete
- its notifications are scoped
- its integration contracts are tested
- its failure states are handled
- its responsive UI is verified
- its migrations are replayable
- its regression tests pass
- its live deployment is verified
- its operational documentation exists
- its owner/approval workflow is defined

---

# 16. Final build principle

Harmony should become a **configurable hospital operating platform**, not a collection of pages copied from a generic HMS specification.

The architecture should grow from the current secure foundation:

**Patient → Appointment → Encounter → Clinical Work → Orders/Results → Treatment → Admission/Care → Billing → Discharge → Follow-up → Reporting → Analytics**

with:

**Authorization + Audit + Notifications + Facility Context + Event Contracts**

running across every stage.

The supplied feature catalogue is therefore incorporated as the **target capability map**, while the actual implementation follows Harmony's existing canonical architecture and reconciles each capability before extending it.
