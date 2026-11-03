BEGIN;

-- Keep the same patient-own and staff access paths, but combine them into one
-- permissive policy per table. The existing restrictive facility policies remain
-- in place and continue to AND with this access union.
DROP POLICY IF EXISTS "patient own invoices select" ON public.invoices;
DROP POLICY IF EXISTS "staff read billing" ON public.invoices;
CREATE POLICY invoices_scoped_read
  ON public.invoices
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.patients p
      WHERE p.id = invoices.patient_id
        AND (
          p.user_id = (SELECT auth.uid())
          OR (
            p.user_id IS NULL
            AND lower(p.email) = lower((SELECT auth.jwt() ->> 'email'))
          )
        )
    )
    OR (SELECT public.current_user_is_clinical_staff())
    OR (SELECT public.current_user_has_role('accountant'::public.app_role))
    OR (SELECT public.current_user_has_role('admin'::public.app_role))
  );

DROP POLICY IF EXISTS "patient own video sessions select" ON public.video_sessions;
DROP POLICY IF EXISTS "staff read telemedicine" ON public.video_sessions;
CREATE POLICY video_sessions_scoped_read
  ON public.video_sessions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.patients p
      WHERE p.id = video_sessions.patient_id
        AND (
          p.user_id = (SELECT auth.uid())
          OR (
            p.user_id IS NULL
            AND lower(p.email) = lower((SELECT auth.jwt() ->> 'email'))
          )
        )
    )
    OR (SELECT public.current_user_is_clinical_staff())
  );

-- Keep the attachment upload authorization unchanged while evaluating auth.uid()
-- once per statement instead of once per candidate row.
DROP POLICY IF EXISTS lab_result_attachments_technician_insert ON public.lab_result_attachments;
CREATE POLICY lab_result_attachments_technician_insert
  ON public.lab_result_attachments
  FOR INSERT TO authenticated
  WITH CHECK (
    facility_id = (SELECT public.current_user_facility_id())
    AND uploaded_by = (SELECT auth.uid())
    AND (
      (SELECT public.current_user_has_role('admin'::public.app_role))
      OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
      OR (SELECT public.current_user_has_role('lab_technician'::public.app_role))
    )
    AND EXISTS (
      SELECT 1
      FROM public.lab_orders lo
      JOIN public.service_orders so
        ON so.related_entity_id = COALESCE(lo.parent_order_id, lo.id)
       AND so.department = 'laboratory'
       AND so.patient_id = lo.patient_id
       AND so.facility_id = lo.facility_id
       AND so.status IN ('released', 'in_progress', 'completed')
      WHERE lo.id = lab_result_attachments.lab_order_id
        AND lo.facility_id = lab_result_attachments.facility_id
    )
  );

-- These SELECT policies duplicate the SELECT arm of the existing ALL policies
-- byte-for-byte. Removing only the redundant SELECT copies preserves the same
-- authorization predicate while avoiding duplicate permissive policy evaluation.
DROP POLICY IF EXISTS payroll_items_admin_it_accountant_select ON public.payroll_items;
DROP POLICY IF EXISTS payroll_periods_admin_it_accountant_select ON public.payroll_periods;

-- Internal notification tables must remain inaccessible to both client roles.
-- One restrictive policy is stronger than two permissive false policies: it
-- continues to deny access even if a permissive policy is accidentally added.
DO $notification_tables$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'notification_audit',
    'notification_deliveries',
    'notification_delivery_logs',
    'notification_inbound_emails',
    'notification_provider_credentials',
    'scheduled_notifications'
  ]
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS notification_internal_deny_anon ON public.%I', table_name);
    EXECUTE format('DROP POLICY IF EXISTS notification_internal_deny_authenticated ON public.%I', table_name);
    EXECUTE format(
      'DROP POLICY IF EXISTS notification_internal_deny_clients ON public.%I',
      table_name
    );
    EXECUTE format(
      'CREATE POLICY notification_internal_deny_clients ON public.%I AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false)',
      table_name
    );
  END LOOP;
END;
$notification_tables$;

COMMIT;
