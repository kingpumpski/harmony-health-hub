# Harmony Health Hub — Evidence-Based Phase & Module Reconciliation

**Audit date:** 2026-10-02  
**Repository baseline:** `18ae866e1d172e76cc8f72ae49171c2049df2595` (main)  
**Roadmap reference:** `docs/HARMONY_NATIONAL_STANDARD_IMPLEMENTATION_BLUEPRINT.md`  
**Purpose:** Establish evidence-based phase gates before adding new HMS capability.

## Status model

A capability is never marked complete from a route, table, migration, or screen alone.

- **Discovered** — referenced in architecture, code, or database.
- **Audited** — relevant layers have been inspected.
- **Implemented** — repository contains a coherent implementation across the required layers.
- **Tested** — repository contracts/tests cover the relevant behavior.
- **Runtime-verified** — live Supabase/browser/runtime behavior has been verified.
- **Production-ready** — security, integrity, observability, operational and deployment requirements are evidenced.
- **Phase-complete** — every applicable module and exit-gate requirement is evidenced.

A phase remains open if any critical module is below the required gate.

## Evidence snapshot

### Repository

The repository contains a broad HMS surface including patient registration/Patient Hub, appointments, encounters, triage/BMI, laboratory, imaging, pharmacy, medication administration, billing, insurance, inpatient, nursing, emergency, theatre, transfusion, maternity, fertility, dental, ophthalmology, procedure notes, telemedicine, AI clinical support, outside-lab handling, reporting, administration, notifications and facility governance.

This establishes **capability presence**, not completion.

### Live Supabase

The current project contains 100+ public tables covering the above domains. All inspected user-data tables have RLS enabled. The live database also contains facility/reporting, notification, audit, test-mode, reference-data and authorization infrastructure.

The live project currently has 11 active Edge Functions, including authenticated administrative, clinical-assist, operational-workspace, notification and document-analysis functions.

### Live security advisor

The security advisor currently reports:

1. Three RLS-enabled test-mode control tables have no policies. This is deny-by-default behavior but should remain explicitly documented and contract-tested.
2. A large set of authenticated-callable SECURITY DEFINER RPCs is reported by the advisor. This is not automatically a vulnerability because many are intentionally server-authoritative workflow endpoints; however, every exposed function must have an explicit authorization contract, restricted EXECUTE grant, and body-level `auth.uid()`/facility/role checks where applicable.
3. Supabase Auth leaked-password protection is currently disabled and remains an infrastructure/security gate item.

Therefore **Phase 0 is not complete**.

## 31-module reconciliation

| # | Master module | Evidence found | Current evidence status | Gate |
|---|---|---|---|---|
| 1 | Clinical Operations | `ClinicalOperations.tsx`, cross-module workflow links, operational workspace RPCs | Implemented surface; end-to-end reconciliation still open | OPEN |
| 2 | Patient Hub / Patients | Patient Hub pages, patient-scoped RPCs, `patients` table, RLS, audit | Implemented; runtime stabilization recently required; full MPI governance not evidenced | OPEN |
| 3 | Registration | Registration UI/workflows, patient persistence and import paths | Implemented surface; duplicate/identifier/consent/merge governance not fully evidenced | OPEN |
| 4 | Appointments | Appointment UI and create/claim/update/start-encounter RPCs | Implemented; runtime issues recently occurred; full notification/no-show/resource scheduling gate open | OPEN |
| 5 | Triage & BMI | Triage UI, BMI context, clinical reference values, partial-measurement migrations | Implemented and heavily tested; clinical flowsheet/EWS/escalation extensions remain open | OPEN |
| 6 | Encounters & Diagnoses | Encounter workspace, clerking, diagnosis/prescription RPCs, signatures/versioning | Implemented; current PR #273 remains unmerged; runtime/browser verification still open | OPEN |
| 7 | Laboratory | Laboratory and results pages, lab lifecycle RPCs/tables, result attention | Implemented surface; analyzer boundary and complete critical-result chain need evidence | OPEN |
| 8 | Pharmacy / Prescriptions / Dispensing | Pharmacy workspace, dispensing/POS/inventory tables and hardening migrations | Implemented surface; full clinical verification/substitution/ADR/FEFO gate open | OPEN |
| 9 | Medication Administration | MAR table, scheduling/transition RPCs, dashboard/notifications | Implemented surface; barcode/device boundary and complete safety reconciliation open | OPEN |
| 10 | Billing & Accounts | Billing UI, billing-window migrations, invoice/payment/service-order workflows | Implemented surface; refund/partial-payment/source-lineage evidence still open | OPEN |
| 11 | Insurance Claims | Claims UI, insurance tables/RPC lifecycle and insurer master data | Implemented surface; end-to-end submission/provider integration not evidenced | OPEN |
| 12 | Ward / Beds / Inpatients | Ward/bed/admission tables, inpatient management and movement workflows | Implemented surface; bed/occupancy/discharge-planning gate open | OPEN |
| 13 | Nursing Handover & Care Plans | Handover/care-plan tables, UI and secure RPCs | Implemented surface; on-duty routing/notification/continuity gate open | OPEN |
| 14 | Emergency | EmergencyBoard and transition/workspace RPCs | Implemented surface; complete triage-priority/escalation/billing chain not evidenced | OPEN |
| 15 | Theatre | TheatreBoard, theatre tables and lifecycle RPCs | Implemented surface; full scheduling/payment/post-op chain not evidenced | OPEN |
| 16 | Anesthesia | Anaesthetic assessment table/RPCs and theatre assignment references | Implemented backend surface; dedicated end-to-end module evidence incomplete | OPEN |
| 17 | Transfusion | TransfusionBoard, transfusion table/RPCs and continuity integration | Implemented surface; compatibility/product traceability/reaction evidence incomplete | OPEN |
| 18 | Maternity | Maternity UI, episode/observation tables and workspace | Implemented surface; labour/delivery/newborn/billing/notifications gate open | OPEN |
| 19 | Fertility | Fertility UI, cycle/monitoring tables | Implemented surface; secure write-path/payment/document/audit reconciliation open | OPEN |
| 20 | Dental | Dental UI/table/workflow evidence | Implemented surface; procedure/service-order/billing/audit gate open | OPEN |
| 21 | Ophthalmology | Ophthalmology UI/table/workflow evidence | Implemented surface; clinical media/storage/provenance/billing gate open | OPEN |
| 22 | Procedure Notes | Procedure UI/table and payment-gate/lifecycle migrations | Implemented surface; complete clinical/billing/signature verification open | OPEN |
| 23 | Telemedicine | Telemedicine UI, video_sessions, lifecycle/billing references | Implemented surface; provider/privacy/payment integration gate open | OPEN |
| 24 | AI Clinical Hub | AI Clinical Hub UI, AI tables, advisory/provenance controls and Edge Function | Implemented advisory surface; safety/source-freshness/audit runtime gate open | OPEN |
| 25 | Inventory / Stock Alerts | Pharmacy inventory, goods receipts, stock hardening and alert paths | Implemented surface; full movement ledger/reservation/FEFO audit gate open | OPEN |
| 26 | Outside Lab | OutsideLabUploads and outside-lab table/analysis path | Implemented surface; order/result/file/payment/provider lifecycle incomplete | OPEN |
| 27 | Reports / Financial Reports | Reports Center pages, report definitions/config/generation/submission tables | Implemented foundation; Ghana statutory extractor/approval/submission evidence incomplete | OPEN |
| 28 | Admissions | AdmissionManagement and admission/discharge RPCs | Implemented; bed/billing/continuity/runtime gate open | OPEN |
| 29 | Care transitions / referrals | Referral/care-transition tables, queues and workflow migrations | Implemented surface; accepting-facility/officer and notification lifecycle incomplete | OPEN |
| 30 | Administration / Users / System Library / Data Import | Admin pages, user Edge Function, imports, reference libraries | Implemented surface; privileged mutation/configuration reconciliation remains open | OPEN |
| 31 | Notifications, audit, permissions, settings and staff shifts | Notification queue/providers/templates/config, audit, RBAC, shifts and test-mode infrastructure | Strong foundation; provider runtime, privileged RPC exposure and test-mode controls remain open | OPEN |

## Phase gate assessment

### Phase 0 — Foundation Governance: **OPEN**

Required evidence is not yet complete. The main blockers are:

- complete authorization/EXECUTE reconciliation for SECURITY DEFINER functions;
- Auth leaked-password protection;
- explicit test-mode control-plane contract;
- complete role → facility → department → permission → data-scope matrix;
- event envelope and idempotency contract coverage;
- runtime verification of foundation workflows.

### Phase 1 — Core Patient Journey: **OPEN**

The core patient journey is substantially implemented, but it cannot be declared complete because:

- Patient Hub and encounter runtime issues have occurred recently;
- PR #273 contains important encounter UI/patient-selection changes and is intentionally unmerged;
- browser/runtime verification of the complete registration → appointment → encounter → documentation → disposition path is outstanding;
- MPI duplicate/merge/consent/provenance governance is not yet evidenced as complete.

### Phase 2 — Diagnostics: **OPEN**

Laboratory and imaging are implemented surfaces, but completion requires evidence for:

- critical-result acknowledgement/escalation;
- analyzer/PACS/DICOM integration boundary;
- result provenance and cumulative views;
- payment/release integration;
- runtime verification.

### Phases 3–11: **NOT STARTED AS PHASE-CERTIFIED**

The repository contains many capabilities mapped to later phases. Their existence does not mean those phases are complete or that the next phase should automatically begin. They remain in the reconciliation queue until their module-level gates are satisfied.

## Immediate implementation order

1. **Gate A — stabilize current Patient Hub + Encounter runtime path.**
2. **Gate B — close Phase 0 foundation/security gaps.**
3. **Gate C — certify Phase 1 core patient journey.**
4. **Gate D — certify Phase 2 diagnostics.**
5. Only then promote the first unverified Phase 3 capability into implementation.

## Evidence required before a module is promoted

For each module, the implementation pass must produce evidence for:

1. canonical schema/migration;
2. RLS and facility boundary;
3. role/permission matrix;
4. protected mutation path;
5. workflow state transitions;
6. audit;
7. notifications/events;
8. billing/payment where applicable;
9. cross-module lineage;
10. loading/empty/error/responsive UI;
11. idempotency/concurrency;
12. repository contracts;
13. typecheck/lint/build;
14. live Supabase verification;
15. browser/runtime verification;
16. documentation and UAT evidence.

**Conclusion:** Harmony has a large amount of implemented capability, but the repository and live database do not provide evidence that any broad phase is complete merely because its screens/tables/RPCs exist. The correct strategy is therefore to reconcile and certify the existing foundation first, then advance one evidence-backed gate at a time.
