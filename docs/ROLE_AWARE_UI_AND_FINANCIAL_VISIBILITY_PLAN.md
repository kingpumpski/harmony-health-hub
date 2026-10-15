# Role-Aware UI and Financial Visibility Cleanup

## Implementation rules

This work is a presentation and workflow cleanup, not a replacement for the platform's authorization model. Sidebar visibility and React conditionals are convenience controls only; route guards, facility-scoped RPCs, PostgreSQL RLS, and function grants remain the enforcement boundary. Do not delete a component, route, RPC, table, or permission merely because it is hidden in one role's UI. Confirm references and authorization dependencies first.

## Role-aware financial workflow matrix

| Active role | Financial UI |
| --- | --- |
| Accountant / Account Officer | Full billing, invoice, payment, claims, tariff and financial-report workspaces. |
| Admin | Read-only, facility-scoped high-level financial overview; no settlement controls. |
| IT Admin / System Superuser | Read-only overview only; no invoice/payment/claim mutation tools. |
| Front Desk | Limited payment verification and approved co-pay collection through existing guarded workflows; no financial reporting or tariff administration. |
| Clinician, nurse, midwife, specialist nurse | No financial widgets or financial navigation. Clinical workflow may show only a non-monetary payment/release status when needed. |
| Laboratory staff | No financial amounts, invoices or billing links. Worklists may show Paid/Pending/Not required when the governed order status supports it. |
| Radiology staff | No financial amounts, invoices or billing links. Worklists may show a non-monetary payment/release status. |
| Pharmacist | No revenue or outstanding-bill KPIs. Worklists may show a non-monetary dispensing/payment status. |
| Patient | Own bills and payments only, via patient-scoped guarded routes/RPCs; never query other patients' financial rows. |

## Dashboard standards

- Top KPI row: no more than four role-specific, actionable metrics.
- Secondary KPI row: no more than four high-level trends; avoid duplicates of the activity feed or primary table.
- Quick Actions: no more than six role-relevant actions; navigation duplicates belong in the sidebar, not quick actions.
- Activity feed: five newest relevant events, sorted newest-first; suppress financial events for non-finance roles and infrastructure/system events from clinical workspaces.
- Avoid duplicating a schedule widget when the appointment KPI already links to the schedule. Keep task detail only when it adds information not available in the KPI/notification surface.
- Keep one refresh control per page/card data surface. Page-level actions belong in the page header; secondary table controls belong in the table toolbar or an overflow menu.
- Search, filters and column selection should remain compact and table-scoped. Keep export/print where the workflow requires it, but avoid duplicate controls.
- Create/Add/New forms stay closed on initial render and open only from the primary action; use the existing modal/drawer pattern.
- Keep error, loading, empty, offline and retry states. Never remove an action that is required for safe completion, audit, accessibility or recovery.

## Navigation and authorization

- Navigation is derived from the active role and existing permission configuration; unknown roles fail closed.
- Accountants retain full financial navigation. Admin, IT Admin and System Superuser see only the read-only Financial Overview. Patients see only their own Billing entry. Front Desk retains only its limited billing entry.
- Clinical and diagnostic roles do not receive Billing, Invoices, Claims, Tariffs or Financial Reports navigation.
- Route guards and server-side permissions must agree with the visible UI. Direct URL access must not bypass this matrix.
- Do not use `auth.uid()` as a patient identifier unless the schema explicitly guarantees identity equality. Patient financial reads must resolve the authenticated patient's linked patient record through a governed RPC or trusted relationship.

## Page-level implementation checklist

1. Inventory buttons, links, KPIs, widgets, and forms on Dashboard, Appointments, Encounters, Laboratory, Radiology, Pharmacy, Billing, Patients, Triage, Ward Management and Administration.
2. Classify each item as primary task, safety-critical, recovery/accessibility, duplicate, unrelated, or unverified. Remove only confirmed duplicates/unrelated items; preserve safety-critical controls.
3. Keep patient registration and clinical care navigation role-specific. Patient portal navigation must never expose staff-management routes.
4. Ensure clinician, laboratory, radiology, pharmacy, nursing and specialist dashboards do not show financial amounts or payment activity.
5. Preserve accountant billing operations and partial-payment workflows.
6. Provide read-only, facility-scoped high-level financial indicators for administrators without payment/claim mutation controls.
7. Verify patient self-service billing remains limited to the signed-in patient's linked patient account.
8. Keep all new forms closed by default and keep one refresh action per data surface.
9. Run typecheck, lint, build, role/dashboard/sidebar/route contracts, authorization/RLS contracts, migration filename/replay contracts and accessibility checks.
10. Use test accounts for each role and record screenshots only for changed UI surfaces. Do not claim a visual audit is complete without actually exercising the role-specific screens.

## Acceptance criteria

- No clinical/diagnostic/specialist role sees financial navigation, revenue KPIs, invoice details, payment amounts or payment activity.
- Lab/radiology/pharmacy worklists expose only a non-monetary status when backed by authoritative workflow state; no guessed payment state.
- Accountant retains all operational settlement actions.
- Admin, IT Admin and System Superuser see a read-only summary, with facility context and server-side role validation.
- Patient billing remains self-only; frontend filtering is not the sole privacy control.
- Dashboard limits and role navigation are covered by automated contract tests.
- No merge until required CI checks pass on the same final head SHA. Do not apply migrations to the live Supabase project as part of this UI cleanup.
