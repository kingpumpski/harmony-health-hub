# Harmony Health Hub Architecture Reconciliation

## Actual stack
- Vite + React 18 + TypeScript.
- React Router 6.
- Tailwind CSS 3.4 with shadcn/Radix primitives.
- TanStack React Query.
- Supabase JS/Auth/PostgREST/RPC/Edge Functions.
- GitHub Pages deployment with BrowserRouter basename.
- Existing offline-aware fetch and continuity/replay infrastructure.

## Existing provider hierarchy
The application root already composes QueryClientProvider, ThemeProvider, AuthProvider, TooltipProvider, notification providers, OfflineStatus and BrowserRouter. There is one AuthProvider in App.tsx.

## Authentication
Authentication is Supabase Auth through src/contexts/AuthContext.tsx. Session persistence is configured by the existing Supabase client. AuthContext restores the session with getSession() and listens to onAuthStateChange. Protected pages use RoleGuard.

The login page previously both navigated immediately after login() and navigated from an authentication effect. The refactor makes authentication readiness the source of truth and prevents duplicate navigation/submission.

## Authorization
Authorization is layered through database/RLS and protected RPC/Edge Function boundaries, database-backed roles, the existing permission catalogue, and client-side RoleGuard. Existing module governance remains authoritative. No second RBAC system is introduced.

## Notifications
Harmony already contains Radix/shadcn toast infrastructure, Sonner, persistent workflow notifications through src/lib/notifications.ts, workflow sound feedback, and a notification centre/preferences. Transient UI feedback remains separate from persistent clinical/operational notifications.

## Data layer
The project mixes React Query, direct Supabase access, RPCs, Edge Functions and domain utilities. Existing offline-aware fetch and replay mechanisms are preserved.

## Record presentation
No single generic record-list primitive previously existed. A reusable RecordList has now been introduced for standard record collections. Specialized clinical workspaces remain specialized.

## Patient Hub
Patient Hub already batches several patient-context RPCs with Promise.allSettled. Counts can be derived from the already loaded authorized patient context without a new schema or endpoint. A shared PatientAvatar has been introduced with safe initials fallback; a persisted photo field/storage migration is intentionally not introduced without an approved schema/storage design.

## Dashboards
Dashboards are role-specific components rather than one generic dashboard. Role-specific operational information must remain intact; simplification should only remove demonstrably redundant presentation.

## Testing
The repository uses contract/regression scripts for operational contracts, offline replay security, role dashboards, sidebar roles, triage and clinical references. No new browser test framework is introduced merely because the generic prompt named one.

## Architectural decisions
1. Supabase Auth remains authoritative.
2. Existing RLS/RPC/Edge Function authorization remains authoritative.
3. Offline continuity remains intact.
4. Specialized clinical boards are not forced into generic tables.
5. Existing UI primitives are extended instead of introducing a new design system.
6. No database schema/storage migration is introduced for avatars.
7. No new dependency is required for this refactor.