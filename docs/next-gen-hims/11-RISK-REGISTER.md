# Next-Generation HIMS Risk Register

| Risk | Impact | Control | Evidence before promotion |
|---|---|---|---|
| Clinical workflow regression | Patient safety / continuity | Preserve canonical workflows; regression suite; clinical review | passing workflow tests |
| Incorrect patient identity match | Wrong-patient care | EMPI confidence thresholds, duplicate review, merge audit | identity test pack |
| Unauthorized PHI access | Privacy / regulatory exposure | deny-by-default RLS, least privilege, audit, MFA/SSO | RLS/security tests |
| AI hallucination or unsafe recommendation | Patient harm | assistive-only posture, source policy, uncertainty, HITL, model lifecycle | AI safety suite |
| Integration message loss/duplication | Diagnostic or operational error | idempotency, retry, DLQ/quarantine, replay, reconciliation | integration replay tests |
| Device data corruption | Incorrect result | registry, validation, QC/calibration metadata, provenance | device fixtures |
| Offline conflict | Data inconsistency | bounded offline scope, deterministic conflict policy, audit | offline recovery tests |
| Schema drift | Runtime failure | additive migrations, replay checks, generated-type reconciliation | migration verification |
| Data residency violation | Legal/regulatory exposure | deployment profiles and residency controls | deployment profile tests |
| Accessibility exclusion | Unsafe/inaccessible care | WCAG 2.2 AA baseline, assistive technology testing | accessibility evidence |
| Notification disclosure | Privacy breach | consent, channel preferences, quiet hours, minimum necessary content | communication tests |
| Supply-chain vulnerability | Security / availability | dependency review, lockfiles, controlled upgrades | dependency audit |
| Deployment mismatch | False quality signal | exact-commit verification and fresh checks | deployment SHA evidence |
| Performance degradation | Operational failure | budgets, profiling, route-level loading, load testing | performance evidence |
| Ransomware / destructive event | Service outage | immutable backups, recovery drills, least privilege | restore exercise |

## Risk acceptance

No high-severity clinical, privacy, security, integrity, or deployment risk may be silently accepted. A temporary exception requires a named owner, documented rationale, compensating control, expiry date, and explicit promotion decision.
