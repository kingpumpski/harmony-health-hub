# Notification provider configuration and SMTP test

## Design boundary

Harmony Health Hub supports multiple notification providers. Provider credentials are deployment secrets, not tenant database data.

Tenant/facility onboarding stores non-secret provider metadata such as provider name, environment, sender identity and a secret_reference. The secret reference identifies where the deployment secret is managed; the credential itself is never written to PostgreSQL.

## Google/Gmail SMTP test

For a Gmail test account:

- SMTP host: smtp.gmail.com
- SMTP port: 465 with SMTP_SECURE=true, or 587 with SMTP_SECURE=false (STARTTLS).
- SMTP username: the Gmail/Google Workspace mailbox.
- SMTP password: a Google App Password, not the normal Google account password.
- SMTP from: normally the same mailbox used for authentication.
- Test recipient: an address you control.

Google states that App Passwords require 2-Step Verification. Nodemailer supports SMTP verification before sending and documents Gmail as a well-known SMTP service.

## GitHub test environment

The repository contains a manual GitHub Actions workflow:

.github/workflows/notification-smtp-test.yml

Create a GitHub environment named notification-test:

1. Open the repository on GitHub.
2. Go to Settings → Environments.
3. Create notification-test.
4. Add these environment secrets:
   - SMTP_HOST
   - SMTP_PORT
   - SMTP_SECURE
   - SMTP_USERNAME
   - SMTP_PASSWORD
   - SMTP_FROM_EMAIL
   - SMTP_TEST_RECIPIENT
5. Manually run Notification SMTP Test from Actions → Notification SMTP Test → Run workflow.

GitHub Actions secrets are encrypted and are only exposed to a workflow when explicitly referenced.

Do not put the SMTP password in repository files, source code, issue comments, pull requests, workflow YAML, or normal GitHub variables.

## Important: GitHub secrets vs production application secrets

The GitHub workflow is deliberately a test harness. It proves that the Google SMTP credentials can authenticate and deliver a controlled message.

It does not make GitHub secrets available to Supabase Edge Functions automatically.

For the actual Harmony notification worker, configure the corresponding secrets in the Supabase project:

NOTIFICATION_EMAIL_PROVIDER=smtp
SMTP_HOST
SMTP_PORT
SMTP_SECURE
SMTP_USERNAME
SMTP_PASSWORD
SMTP_FROM_EMAIL
SMTP_FROM_NAME

Supabase Edge Functions read these values at runtime. Secrets can be added through the Supabase Dashboard or CLI and become available to functions without committing them to Git.

For a tenant-specific production setup, onboarding should capture the provider, environment, sender identity and secret reference, while the actual credential is provisioned into the organization's approved secret-management/deployment boundary.

## Recommended first test

Use a dedicated Google/Gmail or Google Workspace test mailbox and a controlled recipient. Send only the fixed test message from scripts/test-smtp.mjs. Once that succeeds, configure the same provider in the Supabase test environment and enable the email channel for the test facility. Then test:

workflow event → notification_queue → notify-queue-drain → SMTP → notification_delivery_logs

Do not use patient identifiers or clinical content during provider validation.

## Official references

Google App Passwords: https://support.google.com/mail/answer/185833
Nodemailer SMTP: https://nodemailer.com/smtp
GitHub Actions secrets: https://docs.github.com/en/actions/concepts/security/secrets
Supabase Edge Function secrets: https://supabase.com/docs/guides/functions/secrets


## Complete organization/facility onboarding configuration

The notification module is designed so that provider credentials and deployment details are supplied during organization/facility onboarding and again/updated during deployment promotion. The application stores configuration metadata and secret references only.

### Configuration captured during onboarding

- Facility identity: facility ID/code, name, region/district, locale and IANA timezone.
- Delivery policy: quiet hours, critical-alert override, retry/backoff policy, maximum attempts, fallback policy, deduplication window and rollout percentage.
- Channel policy: in-app, email, SMS, push, WhatsApp and voice enablement; per-channel kill switches; critical-event behavior.
- Consent/compliance: external-channel consent requirement, critical override policy, minimum-necessary content, audit retention/erasure policy.
- Branding/sender metadata: organization display name, sender identity, reply-to/contact details and approved sender references.
- Provider metadata: provider, channel, environment (sandbox/test/production), account reference, sender identity, secret reference and verification status.
- Webhook metadata: public callback URL reference, signed-webhook requirement, verification state and idempotency requirement.
- Operational contacts: notification administrator/on-call contact references and escalation ownership.
- Deployment secret namespace/reference: the approved secret-manager/deployment boundary for the organization.

### Deployment secrets/keys/tokens supplied outside the application database

**Email — Resend**
- RESEND_API_KEY
- RESEND_FROM_EMAIL
- RESEND_WEBHOOK_SECRET
- NOTIFICATION_WEBHOOK_PUBLIC_URL

**Email — SMTP**
- NOTIFICATION_EMAIL_PROVIDER=smtp
- SMTP_HOST
- SMTP_PORT
- SMTP_SECURE
- SMTP_USERNAME
- SMTP_PASSWORD
- SMTP_FROM_EMAIL
- SMTP_FROM_NAME

**Push — Firebase Cloud Messaging**
- FCM_PROJECT_ID
- FCM_SERVICE_ACCOUNT_JSON
- Client applications must register FCM device tokens through the notification device registry.

**SMS — Twilio**
- TWILIO_ACCOUNT_SID
- TWILIO_AUTH_TOKEN
- TWILIO_SMS_FROM
- NOTIFICATION_WEBHOOK_PUBLIC_URL when status callbacks are used.

**WhatsApp — Twilio**
- TWILIO_ACCOUNT_SID
- TWILIO_AUTH_TOKEN
- TWILIO_WHATSAPP_FROM
- TWILIO_WHATSAPP_CONTENT_SID for approved Sandbox/test templates
- NOTIFICATION_WEBHOOK_PUBLIC_URL when status callbacks are used.

**Voice — Twilio**
- TWILIO_ACCOUNT_SID
- TWILIO_AUTH_TOKEN
- TWILIO_VOICE_FROM
- TWILIO_VOICE_TWIML_URL
- NOTIFICATION_WEBHOOK_PUBLIC_URL when status callbacks are used.

### Secret-handling rule

Credential values, API keys, access tokens, passwords, private keys and service-account JSON are never entered into normal facility configuration fields and never stored in PostgreSQL. The onboarding form records only the provider metadata and secret reference. The actual values are provisioned into the approved deployment secret boundary before provider verification.

For multi-organization production, each organization's provider credential must resolve from an organization/facility-isolated secret namespace. A single global provider secret must not be treated as tenant-isolated production credentials.

### Go-live sequence

1. Create organization/facility.
2. Initialize notification onboarding automatically.
3. Select channels and providers.
4. Enter non-secret provider metadata and secret references.
5. Provision actual secrets in the deployment environment/secret manager.
6. Verify provider credentials and sender identities.
7. Register push devices where applicable.
8. Configure and verify signed webhooks.
9. Test sandbox/test delivery with synthetic data only.
10. Confirm consent/preferences and quiet-hour policy.
11. Enable channels and set rollout percentage.
12. Run controlled production readiness verification.
13. Promote to production only after the facility-level provider verification gate passes.

External channels remain disabled until this sequence is completed. In-app notifications can remain enabled as the safe baseline.
