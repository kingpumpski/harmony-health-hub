# Notification Module — Phase 10 Reconciliation

## Live migration ledger observation — 2026-09-25

The linked Supabase project contains notification-related migration history under both repository migration names and earlier reconciliation names.

Observed live entries include:

- `20260925161432` → `20260925150000_production_notification_module`
- `20260925161435` → `20260925170000_notification_provider_operationalization`
- `20260925161438` → `20260925181000_notification_queue_service_role_reconciliation`
- `20260925161441` → `20260925182000_notification_facility_onboarding_reconciliation`
- `20260925161443` → `20260925183000_notification_smtp_provider`
- `20260925161446` → `20260925184000_notification_onboarding_configuration_catalog`
- `20260925161449` → `20260925190000_admin_it_notification_settings_control_plane`
- `20260925161522` → `notification_performance_reconciliation`
- `20260925161542` → `notification_facility_policy_finalization`
- `20260925163034` → `notification_advisor_finalization`
- `20260925205231` → `20260925195500_notification_provider_credentials`
- `20260925205248` → `20260925200000_notification_inbound_email_store`
- `20260925210150` → `20260925201500_notification_provider_multi_provider`
- `20260925210206` → `20260925202000_notification_provider_it_admin_multi_provider`
- `20260925210500` → `notification_provider_priority_control_plane`

Earlier entries also exist for `notification_external_fanout_reconciliation`, `facility_notification_onboarding`, and `notification_advisor_reconciliation`.

### Interpretation

The live ledger confirms that the production notification schema and provider-control-plane work has been applied. Supabase records the migration version generated when the migration was applied, so repository filenames should not be treated as literal copies of the live ledger version values.

No migration should be deleted, renamed, or replayed merely to make timestamps match. Future migrations must use a new unique repository version.

## Security boundary

The following notification service tables intentionally remain protected by RLS without browser-facing policies where access is exclusively through server-authorized Edge Functions or service-role workflows:

- `notification_audit`
- `notification_deliveries`
- `notification_delivery_logs`
- `notification_inbound_emails`
- `notification_provider_credentials`
- `scheduled_notifications`

The Supabase security advisor therefore reports `rls_enabled_no_policy` for these six tables. This is a documented service-boundary finding, not permission to expose provider credentials or immutable delivery/audit records to the browser.

The broader project also reports many authenticated-executable `SECURITY DEFINER` functions. These are existing workflow RPCs and must be reviewed individually; notification hardening must not weaken them indiscriminately.

## Phase 10 evidence boundary

Can be verified without a browser: migration/schema contracts, provider authorization logic, encryption contract, facility isolation, priority/primary routing, queue idempotency schema, retry/backoff, circuit breaker, fallback, quiet-hours implementation, scheduler boundary, webhook verification/idempotency, erasure/audit controls, and static UI routing controls.

Still requires live authenticated execution: Admin/IT Admin browser access, provider Save & Test, actual Gmail/Resend delivery, webhook round trip, live retry/fallback delivery, live quiet-hours/DST execution, and load/resilience behavior.

## Merge rule

PR #72 remains unmerged until the remaining live gates are completed and the user explicitly authorizes the Phase 10 merge.
