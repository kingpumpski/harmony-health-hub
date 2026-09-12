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
29. Care Transitions / Referrals
30. Administration / Users / System Library / Data Import
31. Notifications
32. Audit
33. Permissions / RBAC
34. System Settings
35. Staff Shifts

## Reconciliation rules

- Preserve existing canonical tables and workflows; extend them rather than creating duplicate parallel systems.
- Prefer server-authoritative SECURITY DEFINER RPC workflows for protected clinical and financial mutations.
- Direct authenticated table writes must be removed/revoked after the corresponding canonical RPC and UI path are confirmed.
- Patient-sensitive changes require audit coverage with actor and timestamp.
- Chargeable services must respect facility payment routing and service-order release state.
- Clinical decision support, including BMI and AI, remains advisory and must not autonomously prescribe or dose medication.
- Every sidebar route must resolve to an intentional module, not an accidental alias or unrelated page.
- Mobile/small-screen behavior, loading states, empty states, error states and form reset behavior are part of reconciliation.
- Database migrations are part of the module contract; repository migrations must remain replayable in order.
- Live Supabase deployment is considered a separate verification step and must not be claimed until the migration workflow actually succeeds.

## Current reconciliation checkpoints

- **Patient Hub:** implemented with profile, appointments, vitals/triage, encounters, labs, prescriptions, billing, documents and admission tabs; history/error handling and direct-write remnants remain reconciliation targets.
- **Triage & BMI:** server-calculated BMI and secure BMI context are implemented; continue clinical-context and prescribing-safety reconciliation.
- **Encounters:** secure encounter/diagnosis/prescription workflow and BMI context are implemented on `main`; continue verification of all workflow signatures and direct-write lockdown.
- **Appointments:** secure create/claim/update/start-encounter workflow is present; reconcile Patient Hub appointment creation against the same canonical path.
- **Laboratory:** catalogue, sample/result/approval workflow and compatibility reconciliation exist; continue UI/RPC/permission verification.
- **Pharmacy:** payment-gated prescription preparation and dispensing plus inventory handling exist; continue stock, payment, quantity and audit reconciliation.
- **Medication Administration:** secure scheduling/transition/reopen workflow and reminder buckets exist; continue shift-aware notifications and role reconciliation.
- **Billing / Accounts:** service tariffs, invoice-item preparation, payment and service-order release workflows exist; continue duplicate/partial-payment/source-order reconciliation.
- **Insurance / inpatient / emergency / theatre / transfusion / nursing:** secure workflow migrations exist; continue UI-to-RPC and audit/permission reconciliation.
- **Administration / settings / shifts:** core pages exist; continue securing direct configuration/profile writes and completing operational configuration coverage.
- **Notifications / audit / permissions:** foundational components exist; continue ensuring all mutation paths are server-authoritative and role-scoped.

## Required end state

The reconciliation process continues across all 35 items above until the sidebar, routes, pages, database schema, secure workflows, permissions, audit, payment gating, notifications and operational behavior form one coherent HIMS rather than a collection of partially connected screens.
