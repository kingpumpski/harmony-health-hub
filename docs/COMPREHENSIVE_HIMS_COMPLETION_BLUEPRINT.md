# Harmony Health Hub — Comprehensive HIMS Completion Blueprint

## Purpose and implementation rule

Harmony Health Hub is the canonical repository for the hospital-wide Health Information Management System. Extend existing modules, tables, RPCs, routes, hooks, notification infrastructure, audit logs, and facility settings. Do not create parallel implementations where a canonical one exists. This document is a delivery contract, not a claim that every listed capability is already implemented or production-ready.

## 1. Hospital operations modules

### Patient access and identity
- Patient registration, unique MRN, duplicate detection/EMPI, temporary-to-permanent identity reconciliation, demographics, contacts, next of kin, consent, alerts, allergies, insurance, document attachments, patient portal and self-service where enabled.
- Appointments, queues, referrals, triage, vital signs, encounter workspace, clinical notes, diagnosis, orders, care plans, medication reconciliation, procedures, discharge and follow-up.
- Patient Hub as the longitudinal record and single point of access; enforce patient, facility and encounter lineage on all access.

### Clinical specialties and services
- General outpatient, family medicine, internal medicine, paediatrics, obstetrics & gynaecology, maternity, fertility/ART, surgery, anaesthesia, emergency, ICU/HDU, cardiology, neurology, orthopaedics, oncology, nephrology, dermatology, ophthalmology, ENT, dental, psychiatry/mental health, physiotherapy/rehabilitation, nutrition/dietetics, specialist clinics, telemedicine, palliative care and community/public health.
- Specialty configuration must be data-driven: service catalogue, clinic schedules, provider privileges, specialty templates, referral pathways, clinical forms and specialty-specific dashboards.
- Specialist and physiotherapy review queues must be facility-scoped and support pending, scheduled, completed, overdue and cancelled states with safe empty/error states.

### Diagnostics and treatment
- Laboratory catalogue, panels, orders, specimen collection/acceptance/rejection/recollection, analyser/device integration, quality control, result verification/approval, critical-result escalation, attachments and result release.
- Imaging/Radiology using the existing Imaging area: requests, scheduling, modality worklists, reports, image links/PACS/DICOM integration and critical findings.
- Pharmacy: formulary, prescribing, dispensing, medication administration, stock/expiry/batch tracking, interactions/allergy warnings, controlled-drug controls where applicable, returns and reconciliation.
- Theatre/operating room, anaesthesia, recovery, blood bank/transfusion, endoscopy, dialysis and other procedure services as enabled by the facility.
- Maternity, antenatal/postnatal, labour/delivery, newborn/NICU and fertility/IVF workflows remain specialty modules integrated with the same patient identity, encounter, billing and audit foundations.

### Inpatient and emergency
- Emergency arrival, acuity/triage, resuscitation events, observation, transfer and disposition.
- Admission, bed/ward management, bed board, transfers, nursing plans, medication administration, clinical reviews, theatre scheduling, discharge summaries, discharge medications, follow-up and readmission tracking.
- Admission-dependent menus and actions appear only when the patient is admitted; state transitions are validated server-side.

### Revenue cycle and payer operations
- Charge capture, price lists, estimates, invoices, receipts, deposits, refunds/voids with approval, payment allocation, cashier shifts, cash-up, credit control, payer tariffs, eligibility, pre-authorisation, claims preparation/submission/adjudication, rejection/appeal and remittance reconciliation.
- Preserve payment-release rules for billable clinical orders. UI visibility is not authorization; enforce controls in database/RPCs and audit privileged changes.

### Hospital support services
- Inventory, procurement, suppliers, purchase orders, goods received, stock transfers, expiries, asset/equipment maintenance, biomedical engineering and stores.
- Canteen/cafeteria: menus, recipes/ingredients, meal orders, patient diet orders where clinically appropriate, staff/visitor sales, POS, receipts, kitchen preparation, stock consumption, wastage, allergens, dietary restrictions, cash-up and canteen performance reporting. Keep patient clinical diet orders distinct from retail sales and enforce role separation.
- Housekeeping, laundry, facilities, transport/ambulance, security/incident reporting, mortuary, waste management, infection prevention and control, occupational health and health-and-safety workflows.
- HR, payroll, staff credentialing, leave, rosters, attendance, training, credential expiry and provider privileges.

## 2. Roles, permissions and facility boundaries

Support configurable role-to-permission mappings and least privilege, including:
- Platform System Superuser (platform diagnostics and cross-facility administration only through explicit platform-scoped actions)
- Facility Super Admin, Facility Administrator, IT Administrator, Security/Audit Officer
- Medical Director, Department/Clinic Manager, Consultant/Specialist, Medical Officer, Resident/House Officer, Intern
- Nursing Director, Nurse Manager, Registered Nurse, Midwife, Triage Nurse, Nurse Assistant
- Pharmacist, Pharmacy Technician, Lab Manager, Medical Laboratory Scientist/Technician, Radiologist, Radiographer, Sonographer, Blood Bank/Transfusion staff
- Surgeon, Anaesthetist, Theatre Nurse, Theatre Technician, Physiotherapist, Dietitian, Psychologist/Counsellor, Social Worker, Public Health staff
- Receptionist, Appointment Clerk, Medical Records Officer, Referral Coordinator, Billing Officer, Cashier, Accountant, Claims Officer/Adjudicator, Insurance Manager
- Procurement Officer, Storekeeper, Inventory Manager, Canteen Manager, Canteen Cashier, Chef/Kitchen staff, Housekeeper, Laundry staff, Biomedical Engineer, Ambulance/Transport staff, HR Officer, Payroll Officer, Auditor, Researcher and Patient/Guardian portal roles.

Permission dimensions: module, action (read/create/update/approve/release/void/export/administer), facility, department, assigned patient/encounter, data sensitivity and workflow state. Deny by default; validate on server and database, not only sidebar/route. Never let platform administration bypass required facility onboarding, audit logging or clinical safety rules. Test cross-facility reads/writes, inactive users, role changes and direct RPC/API invocation.

## 3. Reporting and analytics center

Provide a single Reporting Center with permission-filtered catalog, saved reports, date/facility/department/specialty/provider filters, drill-down to authorized source records, export permissions, scheduled delivery where configured, and report-run audit logs.

Report groups:
- Operations: registration, appointment utilisation/no-shows, queues, waiting times, referrals, encounters, bed occupancy, admissions, length of stay, discharges and readmissions.
- Clinical quality: diagnoses, outcomes, complications, mortality, infection indicators, adverse events, medication safety, critical results, care gaps and specialty KPIs.
- Diagnostics: lab turnaround, specimen rejection/recollection, pending results, critical-result acknowledgement, imaging turnaround and modality utilisation.
- Pharmacy/stores: dispensing, stock on hand, stock-outs, expiry/wastage, procurement lead time and controlled stock reconciliation.
- Revenue cycle: charges, collections, outstanding balances, refunds, payer ageing, claim acceptance/rejection, adjudication turnaround, denials and remittance variance.
- Canteen: sales, meal volumes, ingredient consumption, food wastage, gross margin and dietary-order fulfilment.
- Workforce/support: staffing/rosters, leave, attendance, credential expiries, equipment downtime, housekeeping and transport performance.
- Governance: user access, privileged actions, audit events, consent, data exports, security incidents, offline sync conflicts and system availability.
- Public health: configurable aggregate disease surveillance, immunisation/maternal-child health and statutory reporting, subject to local requirements and access controls.

Reports must use authoritative, facility-scoped queries; clearly define metric formulas and time zones; avoid exposing patient identifiers in aggregate exports by default; and prevent unauthorized exports.

## 4. Notification Center and workflow events

Extend the existing global Notification Center and notification tables/services rather than creating a second center. Include in-app and Realtime delivery, unread/read state, acknowledgement, severity, recipient/role/facility targeting, deduplication, retry/failure visibility, preferences and audit trail. Optional channels (SMS, email, WhatsApp) require configured providers and consent/appropriate safeguards.

Event categories: appointments/reminders; queue and referral updates; critical lab/imaging results; pending approvals; medication/allergy and stock/expiry alerts; admission/bed/transfer/discharge; billing/payment/claim status; staffing/credential expiry; equipment incidents; canteen orders; security/audit alerts; system health, offline sync and integration failures. Critical clinical alerts require escalation and acknowledgement rules; notifications must not contain unnecessary sensitive patient data.

## 5. Platform-wide foundations

- Facility onboarding/settings, service catalogues, operating hours, departments, specialties, provider schedules, tariffs, payer rules, numbering and configurable workflows.
- Authentication, secure session lifecycle, MFA support where configured, RBAC/ABAC, audit logs, consent, retention, backup/restore and incident response.
- Interoperability foundations: HL7/FHIR, DICOM/PACS, laboratory device protocols and terminology mapping (ICD-10/11 as adopted, SNOMED CT, LOINC); integrations remain disabled until configured and tested.
- Offline-first workflows with durable outbox, idempotency, conflict resolution and a visible Offline Sync Center.
- Accessibility target WCAG 2.2 AA, responsive/mobile-friendly layouts, keyboard navigation, readable error states, loading skeletons and safe empty states.
- AI features must be assistive, traceable and clinician-reviewed; no autonomous diagnosis, prescribing or treatment execution.

## 6. Delivery order and acceptance gates

### Gate A — Reliability and security baseline
1. Reconcile migration order and legacy-schema drift without destructive changes.
2. Require clean database replay, schema/security contract, RLS/privilege tests, typecheck, lint, unit/contract tests, build, navigation/authorization checks and Pages checks.
3. Repair deterministic runtime failures (including missing columns/RPC signatures and undefined UI variables) with forward-only migrations and regression tests.
4. Keep production database pushes disabled until clean replay and legacy-schema validation both pass; do not merge a PR with failing or missing required checks.

### Gate B — Core patient journey
Validate registration → appointment → triage → encounter → diagnosis/orders → results → medication/treatment → billing/payment controls → admission/discharge/follow-up using realistic test facilities and role-specific accounts.

### Gate C — Department workflows
Validate laboratory, imaging, pharmacy, emergency, inpatient/ward, theatre/transfusion, maternity/fertility, specialist/physiotherapy, insurance/claims, HR/payroll, inventory/procurement and canteen.

### Gate D — Management capabilities
Validate Reporting Center, Notification Center, facility settings, audit/security, offline synchronization, integrations and role administration.

### Gate E — Deployment readiness
Complete clinical safety review, privacy/security review, backup/restore rehearsal, performance/accessibility checks, operational runbooks, staff training and a facility sign-off. Test data must be identified and cleared through an approved, auditable process before go-live; never delete live records merely to clean a test environment.

## 7. Definition of done for every module

- A discoverable route and role-appropriate navigation entry; no dead-end buttons or duplicate module implementations.
- Real persisted data and validated forms, with server/database authorization and facility isolation.
- Loading, empty, validation, permission-denied, offline, retry and unexpected-error states.
- Audit events for sensitive reads/changes/approvals/exports where appropriate.
- Database migration and rollback/recovery considerations, RPC/API contract tests and role/facility tests.
- Operational reports and notifications wired to real events where relevant.
- Quality checks pass on the final commit; deployment status is reported accurately.
- No production data/schema mutation until the documented migration gates and explicit approval are satisfied.
