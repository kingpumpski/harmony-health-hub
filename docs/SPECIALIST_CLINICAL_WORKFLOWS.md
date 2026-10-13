# Specialist clinical workflow foundation

This change establishes the database foundation for physiotherapy, ophthalmology, dentistry and dietetics without writing to live patient records.

## Included
- Adds specialist values to `public.app_role` in a separate migration so PostgreSQL can commit enum changes before the values are referenced.
- Adds encounter-linked specialty assessment tables, physiotherapy treatment packages, specialist review tracking and dietary meal orders.
- Adds specialty and session-package metadata to `service_tariffs`.
- Enables RLS on each new clinical table and restricts access to the active facility plus the matching specialist role (or existing administrative troubleshooting roles).
- Adds indexes for patient history, review queues and kitchen meal-order queues.

## Important integration boundary
This is the schema foundation, not the entire end-to-end feature. The React dashboards/forms, role-assignment UI, transactional billing materialization, appointment booking, radiology/lab order RPCs, pharmacy prescription routing, kitchen acknowledgement workflow and browser end-to-end tests must be added in subsequent slices. `specialist_review_sessions.source_assessment_id` deliberately remains a UUID until the polymorphic source is modeled; application RPCs must validate the source against the specialty and facility before use.

## Deployment
Do not apply automatically to the connected database. Review the existing role resolver, tariff schema, active-facility helper, policies, and migration history first; then apply migrations in order in a controlled environment and verify with authenticated users from each role and facility.
