# Security, Privacy and Compliance Specification

## Zero-trust model

Every request is authenticated where required, authorized against tenant/facility/department/user scope, and evaluated against purpose and workflow policy. Frontend route protection never substitutes for server authorization.

## Identity

OIDC/OAuth 2.0-compatible identity, MFA, SSO/federation, passwordless options where supported, session risk controls, privileged-access separation and identity lifecycle management are required capabilities.

## Data protection

Use modern transport encryption, strong encryption at rest, managed/HSM-backed keys where appropriate, key rotation, secrets isolation and strict storage classification. PHI is minimized in logs, URLs, analytics payloads and client persistence.

## Authorization

RBAC is the baseline. ABAC is used where access depends on facility, department, relationship, purpose, care-team membership, break-glass status or jurisdiction. Permissions are deny-by-default.

## Break-glass

Emergency access is time-bound, reason-required, highly audited and reviewable. It does not create unrestricted administrative access.

## Audit

Audit events cover access, create/update/delete, export, consent changes, privileged operations, security events, AI interactions, device integration, clinical-significant decisions and configuration changes. Audit storage is tamper-resistant and retention is policy-driven.

## Privacy engineering

Purpose limitation, data minimization, consent, pseudonymization/de-identification, legal hold, patient rights and data-subject request workflows are built into the platform rather than handled as manual side processes.

## Compliance mapping

The compliance layer maps controls and evidence to ISO/IEC 27001, 27017 and 27018; GDPR and applicable privacy laws; HIPAA where applicable; Australian Privacy Act/My Health Record requirements where applicable; WCAG/Section 508/EN 301 549; and clinical software/device frameworks such as ISO 13485, IEC 62304 and ISO 14971 when a capability falls within their scope.

Standards are treated as implementation targets, not legal certification claims. Deployment profiles must be reviewed by qualified local compliance counsel before market launch.

## Threat model

Threat scenarios include credential compromise, privilege escalation, insider misuse, ransomware, injection, XSS/CSRF/clickjacking, malicious files, data exfiltration, denial of service, supply-chain compromise, integration spoofing, device compromise, AI prompt/context injection and accidental disclosure.

Controls include least privilege, network segmentation, secure headers, content-security policy, malware scanning, dependency governance, secret management, vulnerability management, rate limiting, anomaly detection, incident response and recovery testing.

## Clinical safety convergence

Security failures that could affect patient safety are tracked in the clinical safety register. Clinical hazards that create security requirements are tracked in the security risk register. Shared controls are reviewed jointly.

## Incident response

Incidents are classified by security, privacy, clinical-safety and operational impact. The response process preserves evidence, limits harm, restores service safely and triggers legally required notifications.

## Supply chain

Dependencies, build provenance, lockfiles, package source integrity, vulnerability findings and update decisions are tracked. Security fixes must not be achieved by weakening lint/type/test controls or by adopting untrusted package sources.