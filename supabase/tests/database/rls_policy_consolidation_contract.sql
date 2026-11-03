BEGIN;

SELECT plan(21);

SELECT ok(
  (SELECT count(*) = 1 FROM pg_policy WHERE polrelid='public.invoices'::regclass AND polcmd='r' AND polpermissive),
  'invoices has one consolidated permissive SELECT policy'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy p
    WHERE p.polrelid='public.invoices'::regclass AND p.polname='invoices_scoped_read'
      AND pg_get_expr(p.polqual,p.polrelid) ILIKE '%auth.uid%'
      AND pg_get_expr(p.polqual,p.polrelid) ILIKE '%current_user_is_clinical_staff%'
      AND pg_get_expr(p.polqual,p.polrelid) ILIKE '%accountant%'
      AND pg_get_expr(p.polqual,p.polrelid) ILIKE '%admin%'
  ),
  'invoice patient-own and staff authorization paths are preserved'
);
SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.invoices'::regclass AND polname='facility_identity_select_guard' AND NOT polpermissive),
  'invoice facility identity guard remains restrictive'
);
SELECT ok(
  NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.invoices'::regclass AND polname IN ('patient own invoices select','staff read billing')),
  'superseded invoice SELECT policies are removed'
);

SELECT ok(
  (SELECT count(*) = 1 FROM pg_policy WHERE polrelid='public.video_sessions'::regclass AND polcmd='r' AND polpermissive),
  'video sessions has one consolidated permissive SELECT policy'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy p
    WHERE p.polrelid='public.video_sessions'::regclass AND p.polname='video_sessions_scoped_read'
      AND pg_get_expr(p.polqual,p.polrelid) ILIKE '%auth.uid%'
      AND pg_get_expr(p.polqual,p.polrelid) ILIKE '%current_user_is_clinical_staff%'
  ),
  'video-session patient-own and clinical staff authorization paths are preserved'
);
SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.video_sessions'::regclass AND polname='facility_identity_select_guard' AND NOT polpermissive),
  'video-session facility identity guard remains restrictive'
);
SELECT ok(
  NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.video_sessions'::regclass AND polname IN ('patient own video sessions select','staff read telemedicine')),
  'superseded video-session SELECT policies are removed'
);

SELECT ok(
  (SELECT count(*) = 1 FROM pg_policy WHERE polrelid='public.payroll_items'::regclass AND polcmd IN ('*','r') AND polpermissive),
  'payroll items retains one permissive SELECT policy after duplicate removal'
);
SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.payroll_items'::regclass AND polname='payroll_items_admin_it_accountant_write' AND polcmd='*' AND polpermissive)
  AND NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.payroll_items'::regclass AND polname='payroll_items_admin_it_accountant_select'),
  'payroll items retains its original ALL policy and removes only the duplicate SELECT policy'
);
SELECT ok(
  (SELECT count(*) = 1 FROM pg_policy WHERE polrelid='public.payroll_periods'::regclass AND polcmd IN ('*','r') AND polpermissive),
  'payroll periods retains one permissive SELECT policy after duplicate removal'
);
SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.payroll_periods'::regclass AND polname='payroll_periods_admin_it_accountant_write' AND polcmd='*' AND polpermissive)
  AND NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.payroll_periods'::regclass AND polname='payroll_periods_admin_it_accountant_select'),
  'payroll periods retains its original ALL policy and removes only the duplicate SELECT policy'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid='public.lab_result_attachments'::regclass
      AND polname='lab_result_attachments_technician_insert'
      AND pg_get_expr(polwithcheck,polrelid) ILIKE '%uploaded_by = ( SELECT auth.uid()%'
  ),
  'lab attachment insert policy evaluates auth.uid once per statement'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid='public.lab_result_attachments'::regclass
      AND polname='lab_result_attachments_technician_insert'
      AND pg_get_expr(polwithcheck,polrelid) ILIKE '%service_orders%'
      AND pg_get_expr(polwithcheck,polrelid) ILIKE '%released%'
      AND pg_get_expr(polwithcheck,polrelid) ILIKE '%current_user_facility_id%'
  ),
  'lab attachment insert policy retains facility and released-service-order authorization'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_policy p
    WHERE p.polrelid IN (
      'public.invoices'::regclass,'public.video_sessions'::regclass
    )
    GROUP BY p.polrelid,p.polcmd
    HAVING count(*) FILTER (WHERE p.polpermissive) > 1
  ),
  'invoice and video-session SELECT paths no longer create multiple permissive policies'
);

SELECT ok(
  (SELECT count(*) = 1 FROM pg_policy WHERE polrelid='public.notification_audit'::regclass AND polname='notification_internal_deny_clients' AND NOT polpermissive AND pg_get_expr(polqual,polrelid)='false' AND pg_get_expr(polwithcheck,polrelid)='false'),
  'notification audit is denied to both client roles by one restrictive policy'
);
SELECT ok(
  (SELECT count(*) = 1 FROM pg_policy WHERE polrelid='public.notification_deliveries'::regclass AND polname='notification_internal_deny_clients' AND NOT polpermissive AND pg_get_expr(polqual,polrelid)='false' AND pg_get_expr(polwithcheck,polrelid)='false'),
  'notification deliveries are denied to both client roles by one restrictive policy'
);
SELECT ok(
  (SELECT count(*) = 1 FROM pg_policy WHERE polrelid='public.notification_delivery_logs'::regclass AND polname='notification_internal_deny_clients' AND NOT polpermissive AND pg_get_expr(polqual,polrelid)='false' AND pg_get_expr(polwithcheck,polrelid)='false'),
  'notification delivery logs are denied to both client roles by one restrictive policy'
);
SELECT ok(
  (SELECT count(*) = 1 FROM pg_policy WHERE polrelid='public.notification_inbound_emails'::regclass AND polname='notification_internal_deny_clients' AND NOT polpermissive AND pg_get_expr(polqual,polrelid)='false' AND pg_get_expr(polwithcheck,polrelid)='false'),
  'notification inbound emails are denied to both client roles by one restrictive policy'
);
SELECT ok(
  (SELECT count(*) = 1 FROM pg_policy WHERE polrelid='public.notification_provider_credentials'::regclass AND polname='notification_internal_deny_clients' AND NOT polpermissive AND pg_get_expr(polqual,polrelid)='false' AND pg_get_expr(polwithcheck,polrelid)='false'),
  'notification provider credentials are denied to both client roles by one restrictive policy'
);

SELECT ok(
  (SELECT count(*) = 1 FROM pg_policy WHERE polrelid='public.scheduled_notifications'::regclass AND polname='notification_internal_deny_clients' AND NOT polpermissive AND pg_get_expr(polqual,polrelid)='false' AND pg_get_expr(polwithcheck,polrelid)='false'),
  'scheduled notifications are denied to both client roles by one restrictive policy'
);

SELECT * FROM finish();
ROLLBACK;
