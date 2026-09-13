# Harmony Health Hub — Master Reconciliation List

**Master status:** This document is the canonical reconciliation inventory for the HIMS. Every future reconciliation pass must use this list as the coverage boundary. A module is not considered complete merely because its sidebar item or route exists; UI, route, authorization, database schema/migrations, workflow RPCs, auditability, billing/payment gating where applicable, notifications, error handling and responsive behavior must agree.

## Master modules

1. Clinical Operations
2. Patient Hub / Patients
3. Registration
4. Appointments
5. Triage & BMI
6. Encounters & Diagnoses
7. Laboratory
8. Pharmacy / Prescriptions / Dispensing
9. Medication Administration
10. Billing & Accounts
11. Insurance Claims
12. Ward / Beds / Inpatients
13. Nursing Handover & Care Plans
14. Emergency
15. Theatre
16. Anesthesia
17. Transfusion
18. Maternity
19. Fertility
20. Dental
21. Ophthalmology
22. Procedure Notes
23. Telemedicine
24. AI Clinical Hub
25. Inventory / Stock Alerts
26. Outside Lab
27. Reports / Financial Reports
28. Admissions
29. Care transitions / referrals
30. Administration / Users / System Library / Data Import
31. Notifications, audit, permissions, settings and staff shifts

## Reconciliation standard

Every module is reconciled in this order:

**master module → UI → route → role → permission → database → RLS → secure RPC → workflow state → audit trail → billing/payment → notifications → cross-module integration → error handling → responsive UI**

A module is marked **complete** only when the applicable layers agree. Where a layer is not applicable, the reconciliation record must explicitly say so rather than silently omitting it.

## Reconciliation rules

- Preserve existing canonical tables and workflows; extend them rather than creating duplicate parallel systems.
- Prefer server-authoritative SECURITY DEFINER RPC workflows for protected clinical and financial mutations, with explicit authorization, `auth.uid()` validation and restricted EXECUTE grants.
- Direct authenticated table writes must be removed/revoked after the corresponding canonical RPC and UI path are confirmed.
- Patient-sensitive changes require audit coverage with actor and timestamp.
- Chargeable services must respect facility payment routing and service-order release state.
- Clinical decision support, including BMI and AI, remains advisory and must not autonomously prescribe or dose medication.
- Every sidebar route must resolve to an intentional module, not an accidental alias or unrelated page.
- Mobile/small-screen behavior, loading states, empty states, error states and form reset behavior are part of reconciliation.
- Database migrations are part of the module contract; repository migrations must remain replayable in order.
- Live Supabase deployment is a separate verification step and must not be claimed until the migration workflow actually succeeds.

## Current reconciliation checkpoints

- **Clinical Operations:** workflow dashboard and cross-module operational entry points exist; continue end-to-end permission, queue, billing and notification reconciliation.
- **Patient Hub / Patients:** profile, appointments, vitals/triage, encounters, labs, prescriptions, billing, documents and admission tabs exist; secure workflow entry points are present; direct-read/snapshot and profile-write reconciliation remain targets.
- **Registration:** temporary membership workflow and patient persistence exist; continue duplicate detection, identifier/privacy, audit and registration-to-appointment integration.
- **Appointments:** secure create/claim/update/start-encounter workflow exists; continue role, service-order and notification integration.
- **Triage & BMI:** server-calculated BMI and secure BMI context exist; continue clinical-context and safety reconciliation.
- **Encounters & Diagnoses:** secure encounter/diagnosis/prescription workflow and BMI context exist; continue signature, role and direct-write verification.
- **Laboratory:** catalogue, sample/result/approval workflow and secure entry points exist; continue UI/RPC/permission, payment and result-document reconciliation.
- **Pharmacy / Prescriptions / Dispensing:** payment-gated prescription preparation, dispensing and inventory handling exist; continue stock, payment, quantity, substitutions and audit reconciliation.
- **Medication Administration:** secure scheduling/transition/reopen workflow and reminder buckets exist; continue shift-aware notifications and role reconciliation.
- **Billing & Accounts:** service tariffs, invoice-item preparation, payment and service-order release workflows exist; continue duplicate, partial-payment, refund and source-order reconciliation.
- **Insurance Claims:** secure claim drafting/lifecycle workflows exist; continue financial, submission-event, provider and notification reconciliation.
- **Ward / Beds / Inpatients:** secure ward/unit/bed creation and assignment/release workflows exist; continue admission-bed consistency, occupancy and audit reconciliation.
- **Nursing Handover & Care Plans:** secure creation/review/acknowledgement workflows exist; continue on-duty staff visibility, notifications and patient-continuity integration.
- **Emergency:** secure case creation/assignment/transition exists; continue queue, triage priority, billing and escalation notifications.
- **Theatre:** secure case creation/transition/anesthetist assignment exists; continue procedure payment gating, theatre scheduling and post-op integration.
- **Anesthesia:** secure assessment workflow exists; continue theatre linkage, clearance roles, audit and billing integration.
- **Transfusion:** secure record/event/reaction workflow exists; continue blood-product traceability, compatibility checks, audit and emergency integration.
- **Maternity:** module exists; continue secure write-path, pregnancy episode, labour/delivery, newborn, billing and notification reconciliation.
- **Fertility:** module exists; continue secure clinical write-path, cycle/procedure workflow, payment gating, documents and audit reconciliation.
- **Dental:** secure dental record workflow exists; continue procedure/service-order linkage, billing and audit reconciliation.
- **Ophthalmology:** clinician-recorded examination workflow and secure review exist; continue private clinical media/storage, billing and provenance reconciliation.
- **Procedure Notes:** secure procedure-note workflow exists; continue service-order validation, billing, audit and responsive workflow reconciliation.
- **Telemedicine:** secure scheduling/payment/start/end lifecycle exists; continue binding payment to canonical billable service orders and approved video-provider/privacy controls.
- **AI Clinical Hub:** structured clinical context and advisory provenance exist; continue role boundaries, source freshness, audit and non-autonomous safety controls.
- **Inventory / Stock Alerts:** pharmacy inventory and stock-alert paths exist; continue movement ledger, reorder thresholds, reservations, dispensing consistency and audit.
- **Outside Lab:** outside-lab UI exists; continue secure order/result/file workflow, payment gating, provider tracking, audit and patient continuity integration.
- **Reports / Financial Reports:** report routes exist; continue role-scoped datasets, financial/clinical data separation, export controls and audit.
- **Admissions:** admission lifecycle is now routed through secure RPCs; continue bed linkage, discharge/transfer, billing and continuity reconciliation.
- **Care transitions / referrals:** secure continuity workflow exists; continue referral lifecycle, accepting facility/officer, notifications and longitudinal audit.
- **Administration / Users / System Library / Data Import:** admin pages exist; continue privileged mutation hardening, import validation/audit, role administration and system-library integrity.
- **Notifications, audit, permissions, settings and staff shifts:** server-scoped notification reads, central audit coverage, RBAC/settings/shifts foundations exist; continue privileged-write hardening, on-duty routing, MFA readiness and configuration coverage.

## Required end state

The reconciliation process continues across all 31 items until the sidebar, routes, pages, database schema, secure workflows, permissions, audit, payment gating, notifications and operational behavior form one coherent HIMS rather than a collection of partially connected screens.
