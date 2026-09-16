# Next-Generation HIMS Implementation Status

## Purpose

This document is the living completion ledger for `architecture/next-gen-hims-platform`. It distinguishes architectural coverage from executable production readiness so that an implemented surface is never mistaken for a validated clinical capability.

## Current release posture

- Branch: `architecture/next-gen-hims-platform`
- Promotion state: development/reference only
- Production enablement: disabled until validation
- Main branch: unchanged by this workstream
- Merge: prohibited until every quality gate has current evidence

## Capability ledger

| Domain | Existing canonical surface | Next-generation contract | Promotion evidence required |
|---|---|---|---|
| Patient identity | Patient registration/search/hub | EMPI contract, duplicate detection and controlled merge | clinical safety, privacy, RLS, audit |
| Appointments | Appointments | lifecycle, claiming, conflict prevention and offline continuity | workflow, concurrency, RLS |
| Encounters | Encounters/consultation | lifecycle and structured clinical documentation | clinical safety, audit |
| Laboratory | Laboratory/requests/results | LIS boundary, device ingestion, QC and reconciliation | interoperability, safety, device validation |
| Imaging | Imaging/radiology | RIS/PACS boundary and DICOM exchange | interoperability, safety, image/report integrity |
| Pharmacy | Pharmacy/MAR | medication ordering, dispensing and administration | medication safety, inventory, audit |
| Inpatient | Admissions/ward/nursing | bed state, handover, transitions and escalation | clinical workflow, downtime recovery |
| Emergency | Emergency board | triage, acuity, queue and escalation | clinical safety, performance |
| Theatre/anesthesia | Theatre board/anesthetic assessment | perioperative lifecycle and safety checks | clinical safety, audit |
| Maternity/fertility | Maternity/Fertility | specialty workflow contracts | clinical safety, privacy |
| Billing/claims | Billing/InsuranceClaims | revenue and payer lifecycle with idempotency | financial integrity, audit |
| Inventory | Existing pharmacy/inventory surface | supply-chain controls and device/material lifecycle | reconciliation, audit |
| Workforce | roster/shift management | workforce scheduling and operational capacity | authorization, continuity, audit |
| Public health | reporting foundation | surveillance/export and population-health boundaries | privacy, jurisdictional review |
| Patient engagement | portal/chat/notifications | consented multichannel communication, language, quiet hours, minimum-necessary disclosure and accessibility | privacy, accessibility, audit |
| Interoperability | existing Supabase functions/integration boundaries | typed envelope, idempotency, collision quarantine, retry, quarantine and authorized replay with durable delivery ledger | security, resilience, conformance |
| Device integration | existing laboratory/imaging surfaces | registry, protocol boundary and lifecycle | vendor validation, safety, security |
| AI clinical | AI Clinical Hub/report tooling | governed model registry, intended/prohibited use, evaluation evidence, provenance and human review | AI safety, privacy, clinical review |
| Deployment/localization | existing application configuration | versioned jurisdiction profile with locale, timezone, currency, residency, regulatory, security and module enablement | migration replay, jurisdiction review, configuration integrity |
| Accessibility | existing responsive UI | persistent user preferences and WCAG-oriented behavior | automated + manual accessibility testing |
| Security/audit | existing auth/RLS/audit foundations | deny-by-default platform controls and traceability | RLS/security review, audit verification |

## Newly implemented runtime and workflow boundaries

- `nextGenIntegrationRuntime.ts`: structural envelope validation, message-idempotency boundary with changed-content collision quarantine, delivery failure classification, exponential retry scheduling, terminal-state protection, maximum-attempt quarantine and explicit authorized replay state transitions.
- `nextGenAIGovernance.ts`: active-model allowlisting, evaluation-evidence enforcement, intended/prohibited-use checks, model/version identity matching, evidence/provenance requirements, confidence bounds and confidence-driven human review.
- `nextGenDeploymentProfile.ts`: effective-date validation, jurisdiction profile resolution, residency/configuration access and duplicate module normalization.
- `nextGenCommunicationPolicy.ts`: channel consent, category consent, language selection, timezone-aware and fail-closed quiet-hour configuration, minimum-necessary handling and explicit emergency override semantics.
- `nextGenRuntimeGuards.ts`: centralized composition boundary for clinical action, AI output, communication and deployment-module enforcement.
- `supabase/migrations/20260915170000_nextgen_communication_consent.sql`: persists explicit emergency communication override consent without exposing patient communication preferences to general authenticated access.
- `supabase/migrations/20260915182000_nextgen_integration_payload_integrity.sql`: enables `pgcrypto`, computes authoritative SHA-256 payload hashes in a database trigger, backfills existing delivery records, and enforces a 64-character lowercase SHA-256 format constraint.
- `supabase/migrations/20260916100000_ai_session_request_workflow_hardening.sql`: makes AI analysis requests atomic with their provenance event and restricts clinician review to completed, provider-generated sessions with persisted output/model provenance.
- `supabase/migrations/20260916103000_nextgen_clinical_audit_convergence.sql`: reuses the canonical clinical audit trigger across appointments, medication administration, laboratory orders/results, imaging orders and insurance claims so the next-generation safety boundary converges on one append-only audit surface rather than introducing a parallel audit system.
- `scripts/test-nextgen-clinical-workflows.mjs`: executable repository-level contract checks for clinical audit convergence, laboratory result lifecycle RPCs, imaging lifecycle RPCs, claims financial integrity and direct-write lockdowns.
- `AIClinicalHub.tsx`: routes analysis requests through the secure atomic RPC rather than separately mutating session state and audit state from the browser.
- `scripts/test-nextgen-runtime.mjs`: executable adversarial contract fixtures compiled against the TypeScript runtime, covering supported interoperability standards, envelope rejection/idempotency/collision handling, retry/quarantine/replay transitions, AI lifecycle/evaluation/prohibited-use/model identity/provenance/human-review controls, communication consent/quiet-hours/timezone/emergency handling, deployment module boundaries and fail-closed clinical actions.

The interoperability runtime's in-memory fingerprint remains a duplicate-detection aid only; it is not treated as the authoritative persisted integrity hash. The durable ledger migration now enforces the cryptographic boundary in PostgreSQL.

The AI clinical workflow now follows a stricter server-side sequence: clinician-owned draft → atomic analysis request plus audit event → provider completion through the existing completion RPC → qualified clinician review only after output and model provenance exist. The browser does not get a direct path to manufacture completion or review state.

The core clinical domains now converge on the existing clinical audit trigger. Existing server-authoritative RPCs remain the mutation boundary for laboratory collection/result approval, imaging start/completion and claims financial changes, while authenticated direct-write access remains locked down. These checks are contractually verified and included in the quality workflow; they are not a substitute for actual database replay/RLS execution.

These boundaries are deliberately transport/configuration/governance primitives. They do not create a parallel clinical source of truth and cannot independently authorize clinical actions.

## Implementation rule

A row is not complete merely because its route exists. Completion requires a connected workflow and evidence for every promotion check. Existing canonical functionality is reused where present; new platform primitives provide contracts and governance rather than parallel copies of clinical truth.

## Required evidence before merge

1. Exact-head GitHub quality workflow passes.
2. Typecheck, lint and production build pass.
3. Contract verification and executable runtime fixtures pass, including integration, AI governance, deployment-profile, communication-policy and clinical-workflow boundaries.
4. All new Supabase migrations replay cleanly against a disposable database and reconcile against the deployed schema.
5. RLS tests demonstrate allowed and denied access for representative roles.
6. Clinical safety scenarios pass, including downtime/recovery and duplicate/concurrent action controls.
7. Interoperability fixtures pass validation, idempotency, collision quarantine, retry, quarantine and authorized replay tests across the supported protocol envelope.
8. Accessibility automated checks pass and keyboard/screen-reader/manual checks are recorded.
9. AI governance tests demonstrate model allowlisting, model/version integrity, provenance, uncertainty and human-review enforcement.
10. Communication tests demonstrate consent, quiet-hours, timezone, language and emergency-override behavior without leaking PHI into telemetry.
11. Deployment-profile tests demonstrate effective-date, jurisdiction, residency and module-boundary behavior.
12. Performance/resilience checks meet the project's agreed thresholds.
13. The deployed artifact is verified against the exact final commit.
14. Only after all evidence is current may the draft PR become merge-ready.

## Known external blocker policy

A Vercel build-rate-limit failure or GitHub Actions infrastructure/startup failure is recorded as an infrastructure blocker. It must not be converted into a false green result by removing checks, weakening assertions, or relying on an older commit. Likewise, absence of the correct connected Supabase project blocks migration replay evidence but does not justify applying migrations to an unrelated project.
