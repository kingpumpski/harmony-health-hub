# Production readiness

## Current engineering baseline

The application is being reconciled against the master HIMS reconciliation list and a server-authoritative workflow model:

- clinical and operational state transitions use SECURITY DEFINER RPCs;
- high-value operational tables have authenticated direct INSERT/UPDATE/DELETE revoked where the UI has been migrated to secure RPCs;
- clinical changes are captured by the central system audit trail;
- payment-gated service orders remain the release boundary for chargeable clinical work;
- sensitive patient continuity access is restricted to clinical/authorized operational roles;
- notification read mutations are user/role scoped through RPCs;
- telemedicine lifecycle mutations are server-authorized;
- ophthalmology no longer displays fabricated AI findings and stores clinician-recorded examinations;
- responsive layouts use mobile-first wrapping and horizontal overflow where dense clinical tables require it;
- repository environment credentials have been removed from tracked files and the browser uses the Supabase publishable key only.

## Connected production project

The intended Harmony Health Hub Supabase project is now identified as project ref `ygqoptvezotdqhtimdkr` and is healthy. The repository contains the ordered migration chain and a GitHub Actions deployment workflow that links to this project.

The connected remote database was last verified to have an empty migration history. Therefore the repository migration chain must be deployed in order before the application can be considered database-ready. Do not describe the project as live-migrated until the migration workflow completes successfully and the resulting schema, functions, RLS policies and advisors are rechecked.

## Required before production go-live

1. Add `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD` as GitHub Actions encrypted secrets; never commit either credential or paste it into source/configuration.
2. Run the Supabase migration workflow in dry-run mode first and inspect the ordered migration plan.
3. Apply the complete migration chain to project `ygqoptvezotdqhtimdkr` only after the dry run is clean; do not use a production reset.
4. Re-check Supabase Security Advisor and Performance Advisor and remediate all high/critical findings.
5. Generate/refresh database types from the deployed schema and reconcile application types where necessary.
6. Run database/RLS tests for every sensitive table, including anonymous denial, authenticated role access, and mutation denial for unauthorized roles.
7. Verify Storage policies for private patient documents and clinical media; patient files must never be exposed through public bucket URLs.
8. Configure production Auth controls: confirmed email/phone requirements as appropriate, rate limits, bot protection and MFA for privileged staff.
9. Configure production secrets only through the hosting/database secret stores. Never ship service-role/secret keys to the browser.
10. Validate payment callbacks/webhooks and reconciliation against real provider sandbox transactions before enabling live payments.
11. Complete browser-level smoke tests for registration, appointment, triage, encounter, laboratory, pharmacy, billing, admission, emergency, theatre, transfusion, claims and notifications.
12. Verify backups, restore procedures, audit-log retention and operational monitoring.
13. Replace demo-grade telemedicine provider configuration with the facility-approved provider and contractual/privacy controls where required.

## Master reconciliation coverage

Every module is reconciled against this sequence: **master module → UI → route → role → permission → database → RLS → secure RPC → workflow state → audit trail → billing/payment → notifications → cross-module integration → error handling → responsive UI**.

Master modules:

1. Clinical Operations
2. Patient Hub / Patients
3. Registration
4. Appointments
5. Triage & BMI
6. Encounters & Diagnoses
7. Laboratory
8. Pharmacy / Prescriptions / Dispensing
9. Medication Administration
10. Billing & Accounts
11. Insurance Claims
12. Ward / Beds / Inpatients
13. Nursing Handover & Care Plans
14. Emergency
15. Theatre
16. Anesthesia
17. Transfusion
18. Maternity
19. Fertility
20. Dental
21. Ophthalmology
22. Procedure Notes
23. Telemedicine
24. AI Clinical Hub
25. Inventory / Stock Alerts
26. Outside Lab
27. Reports / Financial Reports
28. Admissions
29. Care transitions / referrals
30. Administration / Users / System Library / Data Import
31. Notifications, audit, permissions, settings and staff shifts

## Security rule

Do not weaken RLS or re-enable direct authenticated writes merely to make a screen work. If a UI fails after migration, reconcile the UI to the existing secure RPC or add a new audited RPC and migration.
