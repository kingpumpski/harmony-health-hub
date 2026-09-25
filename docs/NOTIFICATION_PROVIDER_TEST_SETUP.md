# Notification provider test-tier setup

The notification module now has provider-native adapters for Email (Resend), Push (Firebase Cloud Messaging), SMS/WhatsApp/Voice (Twilio), plus delivery webhooks.

## Provider status

External channels remain disabled in the database until sandbox/test credentials and recipient consent are configured. This preserves the merge gate and prevents accidental external sends.

### Email — Resend

Environment variables:
- `RESEND_API_KEY`
- `RESEND_FROM_EMAIL`
- `RESEND_WEBHOOK_SECRET`
- `NOTIFICATION_WEBHOOK_PUBLIC_URL`

The worker sends through the Resend API and stores the returned message ID. Resend webhooks update sent/delivered/opened/clicked/bounced/complained states.

Recommended test sequence:
1. Create a Resend account/API key.
2. Configure a verified sending domain or the provider's permitted test sender.
3. Create a webhook pointing to the deployed `notification-webhook` Edge Function.
4. Copy the webhook signing secret to `RESEND_WEBHOOK_SECRET`.
5. Send only to explicitly consented test recipients.
6. Confirm the delivery log progresses through provider events.

### Push — Firebase Cloud Messaging

Environment variables:
- `FCM_PROJECT_ID`
- `FCM_SERVICE_ACCOUNT_JSON`

The server uses the FCM HTTP v1 API with a short-lived OAuth access token. Service-account JSON is stored only as a secret; never commit it.

A client/device must register an FCM token through:
- `register_notification_device(provider='fcm', platform, token)`

The worker then sends to active device tokens. Invalid/retired tokens must be deactivated by the device lifecycle.

Client integration should use Firebase Cloud Messaging and request notification permission only after the user's notification preference/consent flow. The HMP must not silently opt a user into push.

### WhatsApp — Twilio test environment

Environment variables:
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_WHATSAPP_FROM`
- `TWILIO_WHATSAPP_CONTENT_SID` (recommended for trial/template testing)
- `NOTIFICATION_WEBHOOK_PUBLIC_URL`

The worker supports Twilio WhatsApp ContentSid/ContentVariables so the trial/Sandbox appointment template can be exercised without pretending that arbitrary free-form business messages are production-ready.

Important: the Twilio WhatsApp Sandbox/trial is a testing environment. Recipients must join/verify the test environment, and trial restrictions apply. Production WhatsApp requires a properly registered sender/business setup.

### SMS — Twilio test environment

Environment variables:
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_SMS_FROM`
- `NOTIFICATION_WEBHOOK_PUBLIC_URL`

Use only verified/authorized test recipients while the account is in trial mode.

## Enabling a channel

Do not enable external channels merely because credentials exist.

The controlled sequence is:

1. Configure provider secrets.
2. Configure the provider webhook.
3. Create/verify a test recipient.
4. Record channel/category consent.
5. Enable the channel at the database layer for the isolated feature branch/test environment.
6. Send a single test notification with a deterministic idempotency key.
7. Confirm provider response and webhook state.
8. Verify audit and delivery logs.
9. Run retry/fallback tests.
10. Only then include the channel in broader rollout.

## Required secret hygiene

Never place provider API keys, Firebase service-account JSON, Twilio auth tokens, or webhook signing secrets in:
- source files
- migrations
- browser code
- `VITE_*` environment variables
- GitHub comments/PR descriptions

All provider credentials must remain server-side Edge Function secrets.

## Safety defaults

- External channels default disabled.
- In-app remains the baseline channel.
- Critical clinical events can bypass quiet hours according to the clinical escalation policy.
- Non-critical notifications remain subject to user preferences and consent.
- Push requires an active device token.
- WhatsApp trial restrictions are not treated as production capabilities.
- Provider failure never blocks the clinical transaction; it remains asynchronous and auditable.

## References

Provider documentation should be checked again immediately before enabling a provider because free/test quotas and trial restrictions can change.


## Production organization/facility onboarding

Provider settings are designed to be configured **when an organization/facility is created, onboarded or registered**, rather than hard-coded into the application.

The onboarding flow should collect:

1. Organization/facility identity and facility scope.
2. Default locale and IANA timezone.
3. Notification policy and quiet hours.
4. Channels the organization intends to offer.
5. Provider selection per channel: Email, Push, WhatsApp, SMS and Voice.
6. Provider account/sender identifiers.
7. Provider secret references.
8. Webhook endpoint/verification configuration.
9. Organization branding/sender identity.
10. Consent wording and external-channel policy.
11. Sandbox/test versus production environment.
12. Rollout percentage and emergency kill switch.

### Credential boundary

The onboarding UI must **never store provider API secrets in ordinary organization configuration tables**. The onboarding workflow stores only a non-secret reference such as a secret identifier. Actual credentials are provisioned into the server-side secret manager/environment used by the notification Edge Functions.

This permits each organization to onboard its own provider configuration without exposing secrets to patients, browser code or ordinary application tables.

### Production readiness sequence

Organization registration → notification onboarding initialized → provider connections configured → sandbox/test credentials verified → consent verified → test notifications delivered → webhooks verified → audit/delivery tracking verified → organization marked `production_ready` → controlled rollout → full enablement.

The database function `mark_facility_notification_production_ready` intentionally refuses to enable production until the onboarding state has reached `sandbox_ready` or `verification_pending`.
