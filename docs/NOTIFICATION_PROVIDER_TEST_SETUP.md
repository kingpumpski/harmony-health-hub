# Notification provider configuration and SMTP test

## Design boundary

Harmony Health Hub supports multiple notification providers. Provider credentials must never be stored in PostgreSQL as plaintext, committed to source control, or exposed to browser code.

There are two supported provider-secret paths:

1. **Facility-managed application configuration:** IT Administrators/Administrators submit provider credentials through the protected System Settings surface. The server-side Edge Function encrypts the credential values with `NOTIFICATION_CREDENTIAL_ENCRYPTION_KEY` before storing ciphertext in the provider-credential table. Plaintext credentials are never returned to the UI.
2. **Deployment-level provider secrets:** deployment-wide credentials can be supplied as Supabase Edge Function secrets. These are runtime secrets and are not stored in the application database.

Facility onboarding stores provider metadata such as provider, channel, environment, sender identity, account reference, priority, primary designation, verification status and secret reference. Where the application-managed credential path is used, only encrypted ciphertext is retained in PostgreSQL.

## Google/Gmail SMTP test

For a Gmail test account:

- SMTP host: smtp.gmail.com
- **Hosted Supabase Edge Function runtime:** use port **465** with `SMTP_SECURE=true`. Ports 25 and 587 are rejected by the notification worker because hosted Supabase Edge Functions do not permit those outbound SMTP ports.
- **GitHub Actions CI harness:** port 587 with `SMTP_SECURE=false` is acceptable because the workflow runs outside Supabase.
- SMTP username: the Gmail/Google Workspace mailbox.
- SMTP password: a Google App Password, not the normal Google account password.
- SMTP from: normally the same mailbox used for authentication.
- Test recipient: an address you control.

Google states that App Passwords require 2-Step Verification. Nodemailer supports SMTP verification before sending and documents Gmail as a well-known SMTP service.

## GitHub test environment

The repository contains a manual GitHub Actions workflow:

`.github/workflows/notification-smtp-test.yml`

Create a GitHub environment named `notification-test`:

1. Open the repository on GitHub.
2. Go to Settings → Environments.
3. Create `notification-test`.
4. Add these **environment variables**:
   - `SMTP_HOST`
   - `SMTP_PORT`
   - `SMTP_SECURE`
   - `SMTP_TEST_RECIPIENT`
5. Add these **environment secrets**:
   - `SMTP_USERNAME`
   - `SMTP_PASSWORD`
   - `SMTP_FROM_EMAIL`
6. Manually run **Notification SMTP Test** from Actions → Notification SMTP Test → Run workflow.
7. Set the `test_ref` input to the feature branch when testing the isolated notification implementation.

GitHub Actions secrets are encrypted and are only exposed to a workflow when explicitly referenced. Non-secret test configuration can use GitHub Actions Variables.

Do not put the SMTP password, Google App Password, API key, private key, or service-account JSON in repository files, source code, issue comments, pull requests, workflow YAML, or normal GitHub variables.

## Important: GitHub CI secrets vs production application secrets

The GitHub workflow is deliberately a CI/test harness. It proves that the Google SMTP credentials can authenticate and deliver a controlled message. It does **not** make GitHub secrets available to Supabase Edge Functions automatically.

For the actual Harmony notification worker, deployment-level configuration may include:

`NOTIFICATION_EMAIL_PROVIDER=smtp`
`SMTP_HOST`
`SMTP_PORT`
`SMTP_SECURE`
`SMTP_USERNAME`
`SMTP_PASSWORD`
`SMTP_FROM_EMAIL`
`SMTP_FROM_NAME`

For facility-managed provider configuration, use **System Settings → Email Service Configuration**. The application encrypts the submitted provider credentials server-side and stores only ciphertext. The required platform secret is:

`NOTIFICATION_CREDENTIAL_ENCRYPTION_KEY`

It must be base64-encoded and decode to exactly 32 bytes. Never expose this key to the frontend or store it in PostgreSQL.

## Recommended first test

Use a dedicated Google/Gmail or Google Workspace test mailbox and a controlled recipient. Send only the fixed test message from `scripts/test-smtp.mjs`. Once that succeeds, configure the same provider in the Supabase test environment and enable the email channel for the test facility. Then test:

workflow event → notification_queue → notify-queue-drain → SMTP → notification_delivery_logs

Do not use patient identifiers or clinical content during provider validation.

## Official references

Google App Passwords: https://support.google.com/mail/answer/185833
Nodemailer SMTP: https://nodemailer.com/smtp
GitHub Actions secrets: https://docs.github.com/en/actions/concepts/security/secrets
Supabase Edge Function secrets: https://supabase.com/docs/guides/functions/secrets


## Complete organization/facility onboarding configuration

The notification module is designed so that provider credentials and deployment details are supplied during organization/facility onboarding and again/updated during deployment promotion. The application stores provider metadata and, when using facility-managed configuration, encrypted provider ciphertext. Plaintext credentials remain outside the database and are never returned to the UI.

### Configuration captured during onboarding

- Facility identity: facility ID/code, name, region/district, locale and IANA timezone.
- Delivery policy: quiet hours, critical-alert override, retry/backoff policy, maximum attempts, fallback policy, deduplication window and rollout percentage.
- Channel policy: in-app, email, SMS, push, WhatsApp and voice enablement; per-channel kill switches; critical-event behavior.
- Consent/compliance: external-channel consent requirement, critical override policy, minimum-necessary content, audit retention/erasure policy.
- Branding/sender metadata: organization display name, sender identity, reply-to/contact details and approved sender references.
- Provider metadata: provider, channel, environment (sandbox/test/production), account reference, sender identity, secret reference, priority, primary designation and verification status.
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

Credential values, API keys, access tokens, passwords, private keys and service-account JSON are never stored in PostgreSQL as plaintext.

For the **facility-managed provider path**, the server encrypts credential values before persistence. The database may therefore contain encrypted ciphertext and non-secret metadata, but it must never contain recoverable plaintext credentials in normal columns or JSON metadata. The encryption key remains a deployment secret and is not stored with the ciphertext.

For the **deployment-level provider path**, credentials remain in the deployment secret store and are read only by server-side Edge Functions.

For multi-organization production, each organization's provider credential must resolve from an organization/facility-isolated secret namespace or an equivalent encrypted credential boundary. A single global provider secret must not be treated as tenant-isolated production credentials.

### Go-live sequence

1. Create organization/facility.
2. Initialize notification onboarding automatically.
3. Select channels and providers.
4. Enter non-secret provider metadata and, when using the application-managed path, submit credentials only through the protected provider configuration surface.
5. Provision deployment-level secrets where required.
6. Verify provider credentials and sender identities.
7. Register push devices where applicable.
8. Configure and verify signed webhooks.
9. Test sandbox/test delivery with synthetic data only.
10. Confirm consent/preferences and quiet-hour policy.
11. Enable channels and set rollout percentage.
12. Run controlled production readiness verification.
13. Promote to production only after the facility-level provider verification gate passes.

External channels remain disabled until this sequence is completed. In-app notifications can remain enabled as the safe baseline.


## Facility-managed email providers

IT Administrators and Administrators can configure facility email providers from **System Settings → Email Service Configuration**. Supported providers are Resend and SMTP. Provider credentials are encrypted server-side and are never returned to the UI after submission.

Multiple verified email providers may coexist for the same facility/environment. Each provider has a numeric **priority** (lower numbers are attempted first) and an optional **primary** designation. Only one provider can be primary for a facility/channel/environment. Delivery records each provider attempt, and the worker proceeds to the next configured provider before falling back to the next notification channel.

The application requires the Supabase Edge Function secret `NOTIFICATION_CREDENTIAL_ENCRYPTION_KEY`, encoded as base64 and decoding to exactly 32 bytes. This is a platform-level encryption key; facility SMTP/Resend credentials are stored only as encrypted ciphertext. Do not place provider passwords, API keys, or app passwords in PostgreSQL plaintext, frontend environment variables, or source control.

The existing GitHub Actions SMTP workflow remains a controlled CI test harness. It is not the tenant/facility provider configuration path.

### Hosted Supabase SMTP constraint

For hosted Supabase Edge Functions, outbound connections to SMTP ports **25 and 587 are not allowed**. The notification worker therefore rejects those ports explicitly. For Gmail SMTP runtime delivery, use SSL on port **465** with `secure=true`, if the provider/network path permits it, or use Resend/another HTTPS-based provider for production delivery. The GitHub Actions SMTP harness runs outside Supabase and can use port 587 for CI validation.
