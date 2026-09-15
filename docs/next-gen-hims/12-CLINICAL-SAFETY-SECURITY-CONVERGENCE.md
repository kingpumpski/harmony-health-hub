# Clinical Safety and Security Convergence

Healthcare security controls are clinical safety controls when compromise, denial, corruption, or unauthorized disclosure can change care. The reference platform therefore treats cybersecurity, privacy, data integrity, resilience, and clinical safety as one assurance system with domain-specific controls.

## Shared control model

1. **Identify** — patient, actor, device, data classification, clinical context, and intended operation.
2. **Authorize** — role/attribute checks, least privilege, consent, purpose limitation, and break-glass rules where applicable.
3. **Validate** — input/schema/terminology/device provenance and clinical workflow preconditions.
4. **Execute** — idempotent, transactional, observable domain operation.
5. **Record** — durable clinical/business record plus security/audit evidence.
6. **Communicate** — minimum necessary information through consented channels.
7. **Recover** — retry, quarantine, reconciliation, rollback or human escalation according to risk.
8. **Review** — safety, privacy, security and operational monitoring with explicit ownership.

## High-risk convergence points

- Patient identity and demographic changes
- Medication prescribing, dispensing and administration
- Laboratory and imaging result ingestion
- Blood bank and transfusion workflows
- Emergency and triage decisions
- Theatre and anesthesia workflows
- Maternity and fertility clinical records
- Claims, billing and financial approvals
- AI-generated clinical content
- Device-originated observations
- Offline synchronization and conflict resolution
- Break-glass access and privileged administration

## AI-specific convergence

AI output is untrusted until validated in context. The platform must retain model identity/version, intended-use classification, relevant source/provenance metadata, uncertainty or confidence information where available, reviewer identity, and final disposition. A model must never silently convert an advisory suggestion into an autonomous clinical order or diagnosis.

## Release evidence

A high-risk workflow is not promotion-ready until both its clinical safety case and security/privacy case are evidenced. Passing only an application build or static analysis check is insufficient.
