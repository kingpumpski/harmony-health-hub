BEGIN;

SELECT plan(29);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.appointments'::regclass AND polname='staff manage appointments' AND polcmd='*' AND polpermissive)
  AND EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.appointments'::regclass AND polname='patient own appointments select' AND polcmd='r' AND polpermissive),
  'patient ownership and staff management remain separate, intentional SELECT access paths'
);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.dental_assessments'::regclass AND polname='dental_assessments_facility_access' AND polcmd='*' AND polpermissive)
  AND EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.dental_assessments'::regclass AND polname='dental_assessments_clinical_read' AND polcmd='r' AND polpermissive),
  'dental specialty write access and clinical read access remain distinct'
);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.dietary_assessments'::regclass AND polname='dietary_assessments_facility_access' AND polcmd='*' AND polpermissive)
  AND EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.dietary_assessments'::regclass AND polname='dietary_assessments_clinical_read' AND polcmd='r' AND polpermissive),
  'dietician write access and clinical read access remain distinct'
);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.dietary_meal_orders'::regclass AND polname='dietary_meal_orders_facility_access' AND polcmd='*' AND polpermissive)
  AND EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.dietary_meal_orders'::regclass AND polname='dietary_meal_orders_clinical_read' AND polcmd='r' AND polpermissive),
  'meal-order specialty write access and clinical read access remain distinct'
);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.ophthalmology_assessments'::regclass AND polname='ophthalmology_assessments_facility_access' AND polcmd='*' AND polpermissive)
  AND EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.ophthalmology_assessments'::regclass AND polname='ophthalmology_assessments_clinical_read' AND polcmd='r' AND polpermissive),
  'ophthalmology specialty write access and clinical read access remain distinct'
);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.physio_assessments'::regclass AND polname='physio_assessments_facility_access' AND polcmd='*' AND polpermissive)
  AND EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.physio_assessments'::regclass AND polname='physio_assessments_clinical_read' AND polcmd='r' AND polpermissive),
  'physiotherapy specialty write access and clinical read access remain distinct'
);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.physio_treatment_plans'::regclass AND polname='physio_treatment_plans_facility_access' AND polcmd='*' AND polpermissive)
  AND EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.physio_treatment_plans'::regclass AND polname='physio_treatment_plans_clinical_read' AND polcmd='r' AND polpermissive),
  'physiotherapy treatment-plan write access and clinical read access remain distinct'
);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.specialist_review_sessions'::regclass AND polname='specialist_review_sessions_facility_access' AND polcmd='*' AND polpermissive)
  AND EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.specialist_review_sessions'::regclass AND polname='specialist_review_sessions_clinical_read' AND polcmd='r' AND polpermissive),
  'specialty-specific review access and general clinical read access remain distinct'
);

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
