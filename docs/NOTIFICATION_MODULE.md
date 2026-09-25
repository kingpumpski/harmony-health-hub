# Production Notification Module

## Architecture

`mermaid`
flowchart LR
A[Domain modules] --> B[Event Contract]
B --> C[(Notification Queue)]
C --> D[Async Worker]
D --> E[Preference + Consent]
E --> F[Template + i18n]
F --> G[Channel Router]
G --> H[In-App]
G --> I[Email]
G --> J[SMS]
G --> K[Push]
G --> L[WhatsApp]
G --> M[Voice]
H --> N[(Notifications + Realtime)]
I --> O[(Delivery Logs)]
J --> O
K --> O
L --> O
M --> O
D --> P[(Immutable Audit)]
G --> Q[Retry + Fallback]
Q --> D
`

## Existing architecture reconciled
- Retains the existing `notifications` table, secure read RPCs, realtime surface, notification queue and queue-drain worker.
- Adds event catalog, templates, preferences/consent, scheduling, delivery logs, immutable audit, feature flags and an authenticated send Edge Function.
- Provider calls occur only in the asynchronous worker. Clinical/application transactions enqueue work and return without waiting for providers.

## Folder structure
- `src/lib/notifications`: contracts, dispatcher, preferences, templates, scheduler and feature flags.
- `supabase/functions/notifications-send`: authenticated 202-style enqueue endpoint.
- `supabase/functions/notify-queue-drain`: asynchronous channel router with retry/fallback.
- `supabase/functions/notification-scheduler`: scheduled-notification handoff worker.
- `supabase/migrations`: production schema and event/template seed.
- `supabase/tests/database`: database contract checks.

## Data model
Core tables: `notifications`, `notification_queue`, `notification_events`, `notification_templates`, `notification_channels`, `user_notification_preferences`, `notification_consent_audit`, `scheduled_notifications`, `notification_delivery_logs`, `notification_audit`, `notification_feature_flags`.

Queue idempotency is enforced by a unique `idempotency_key`. Delivery attempts are append-only records. Audit mutation is blocked by a database trigger.

## Event catalog coverage
Implemented seed catalog covers appointment lifecycle, consultation/diagnosis/treatment, laboratory, medication, discharge/post-care, reviews, wellness/greetings, account/security, billing, critical clinical alerts, public-health alerts and reactivation. Additional events can be inserted without schema changes.

## Template policy
Templates are keyed by event and locale. Variables are HTML-escaped by the shared renderer. External-channel templates should contain minimum necessary information; clinical details remain behind authenticated application links.

## API contracts
- `POST /notifications/send`: Edge Function `notifications-send`, returns `202` with `queue_id`.
- `POST /notifications/schedule`: persists `scheduled_notifications`; scheduler worker later enqueues it.
- `GET /notifications`: existing recipient-scoped workflow notification RPC.
- `PATCH /notifications/:id/read`: existing `mark_notification_read` RPC.
- `GET/PUT /notifications/preferences`: preference-center page + authenticated preference store.
- `WS /ws/notifications`: Supabase Realtime for recipient-safe in-app updates.

## Channel delivery
- In-app: enabled by default and persisted in `notifications`.
- Email/SMS/WhatsApp/voice: provider adapters are implemented behind environment configuration and disabled by default.
- Push: intentionally remains gated until a device-token registry is available; the worker records a non-delivery rather than fabricating a push.
- External failure proceeds to the next permitted channel; retryable failures use exponential backoff.

## Scheduling
All persisted instants are UTC. Recipient timezone is stored as an IANA timezone. Quiet hours default to 22:00–07:00 local time; critical events use send behavior. The scheduler never performs provider calls.

## Compliance and safety
- Server-authoritative consent and preference checks.
- No provider credentials in browser code.
- Generic external critical-alert content avoids exposing PHI.
- Consent changes have timestamps, IP and version fields.
- Delivery and audit evidence is queryable; audit rows are immutable.

## Test plan
- Static contract checks in `scripts/validate-operational-contracts.mjs`.
- Database contract assertions in `supabase/tests/database/notification_module_contract.sql`.
- Required next CI gates: TypeScript, ESLint, database migration dry-run, Edge Function typecheck, integration tests for enqueue → worker → delivery → fallback, provider sandbox contract tests, timezone/DST tests, idempotency tests, quiet-hour tests, auth/RLS tests and load testing at 10k notifications/minute.

## Rollout
1. In-app/internal only.
2. Category flags: 5%.
3. 25%.
4. 100%.
5. Enable each external provider independently after sandbox and consent review.
6. Preserve per-channel/per-event kill switches.

## Standout roadmap
Send-time optimization, fatigue caps, contextual wellness, caregiver consent, two-way SMS/WhatsApp, voice escalation, wearable integration, symptom-check links and public-health feeds remain controlled extensions. AI-generated health content must remain assistive and never make autonomous clinical decisions.