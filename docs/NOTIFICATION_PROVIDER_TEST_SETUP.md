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
