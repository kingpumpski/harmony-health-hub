# Production readiness

## Current engineering baseline

The application is being reconciled against a server-authoritative HIMS model:

- clinical and operational state transitions use SECURITY DEFINER RPCs;
- high-value operational tables have authenticated direct INSERT/UPDATE/DELETE revoked where the UI has been migrated to secure RPCs;
- clinical changes are captured by the central system audit trail;
- payment-gated service orders remain the release boundary for chargeable clinical work;
- sensitive patient continuity access is restricted to clinical/authorized operational roles;
- notification read mutations are user/role scoped through RPCs;
- telemedicine lifecycle mutations are server-authorized;
- ophthalmology no longer displays fabricated AI findings and stores clinician-recorded examinations;
- responsive layouts use mobile-first wrapping and horizontal overflow where dense clinical tables require it.

## Required before production go-live

1. Apply the complete migration chain to the intended production Supabase project and verify every migration succeeds in order.
2. Run Supabase Security Advisor and Performance Advisor and remediate all high/critical findings.
3. Run database/RLS tests for every sensitive table, including anonymous denial, authenticated role access, and mutation denial for unauthorized roles.
4. Verify Storage policies for private patient documents; patient files must never be exposed through public bucket URLs.
5. Configure production Auth controls: confirmed email/phone requirements as appropriate, rate limits, bot protection and MFA for privileged staff.
6. Configure production secrets only through the hosting/database secret stores. Never ship service-role/secret keys to the browser.
7. Validate payment callbacks/webhooks and reconciliation against real provider sandbox transactions before enabling live payments.
8. Complete browser-level smoke tests for registration, appointment, triage, encounter, laboratory, pharmacy, billing, admission, emergency, theatre, transfusion, claims and notifications.
9. Verify backups, restore procedures, audit-log retention and operational monitoring.
10. Replace demo-grade telemedicine provider configuration with the facility-approved provider and contractual/privacy controls where required.

## Known repository-side limitation

The GitHub repository contains the migration chain, but the connected Supabase account currently does not expose the Harmony Health Hub production project. Therefore repository migrations must not be described as live-deployed until the correct production project is connected and the migration workflow completes successfully.

## Security rule

Do not weaken RLS or re-enable direct authenticated writes merely to make a screen work. If a UI fails after migration, reconcile the UI to the existing secure RPC or add a new audited RPC and migration.
