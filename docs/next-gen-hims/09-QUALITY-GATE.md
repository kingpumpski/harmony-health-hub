# Next-Generation HIMS — Non-Mergeable Quality Gate

## Gate 0 — Repository integrity

- working tree is intentional;
- branch is based on the latest approved main baseline;
- no unresolved merge conflicts;
- no generated secrets or PHI fixtures;
- migration filenames are ordered and unique.

## Gate 1 — Static quality

- dependency installation succeeds from lockfile;
- lint succeeds without disabling rules to hide defects;
- TypeScript/type validation succeeds;
- production build succeeds;
- no stale generated artifacts are relied upon.

## Gate 2 — Database integrity

- every migration replays from a clean database;
- existing migrations remain replayable in order;
- RLS is enabled on sensitive new tables;
- policies are least privilege;
- security-definer workflows use fixed search paths and explicit authorization;
- direct writes are not accidentally exposed where a secure workflow is required;
- schema contracts match frontend and workflow expectations.

## Gate 3 — Clinical workflow safety

For each affected workflow verify happy path, invalid input, unauthorized actor, concurrent actor, duplicate submission, cancellation, retry, timeout, partial completion and recovery. Safety-critical workflows require clinical review.

## Gate 4 — Interoperability

Validate FHIR resources, HL7 v2 fixtures, DICOM workflows and ASTM/device messages applicable to the implemented capability. Verify provenance, ordering, idempotency, replay, rejection and dead-letter behavior.

## Gate 5 — Accessibility

Core workflows must pass automated accessibility checks plus keyboard-only, screen-reader, zoom/reflow, contrast, reduced-motion and touch/alternative-input checks. Patient-facing workflows additionally require plain-language and communication-modality review.

## Gate 6 — Security and privacy

Threat model, authorization-negative tests, file security, dependency review, secret handling, CSP/security headers, PHI-safe logging, audit integrity, break-glass controls and incident pathways must be verified.

## Gate 7 — AI safety

For AI-enabled features verify intended use, prohibited use, human oversight, confidence/uncertainty behavior, source provenance, model/version capture, prompt/context injection resistance, data minimization, bias evaluation and override/audit behavior.

## Gate 8 — Resilience and performance

Test offline staging and synchronization, conflict resolution, retry/idempotency, degraded dependencies, large datasets, concurrency, latency budgets and recovery. No critical workflow may silently fail because connectivity disappears.

## Gate 9 — Deployment verification

Run the actual target deployment pipeline. Verify deployed build identity, database migration state, runtime configuration, service-worker/cache state, critical routes, authentication, representative workflows and observability. A local green build is not deployment proof.

## Gate 10 — Traceability

Every implemented requirement maps to module, UI/route, authorization, data contract, migration, workflow, audit, notification/integration dependencies and tests.

## Merge rule

No merge to `main` while any gate is unknown, failed, stale or dependent on manual assumptions. A previous green run is invalid if it predates the commit under review.