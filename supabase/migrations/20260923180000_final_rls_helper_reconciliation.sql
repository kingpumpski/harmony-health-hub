-- Final RLS reconciliation for the intentionally non-client-callable
-- is_clinical_staff(UUID) helper. Policies use the current-user helper instead.

DROP POLICY IF EXISTS billing_overrides_staff_read ON public.billing_overrides;
CREATE POLICY billing_overrides_staff_read ON public.billing_overrides
FOR SELECT TO authenticated
USING (
  public.current_user_has_role('admin')
  OR public.current_user_has_role('accountant')
  OR public.current_user_is_clinical_staff()
);

DROP POLICY IF EXISTS document_versions_staff_read ON public.document_versions;
CREATE POLICY document_versions_staff_read ON public.document_versions
FOR SELECT TO authenticated
USING (
  public.current_user_has_role('admin')
  OR changed_by=(SELECT auth.uid())
  OR public.current_user_is_clinical_staff()
);

DROP POLICY IF EXISTS imaging_orders_clinical_insert ON public.imaging_orders;
CREATE POLICY imaging_orders_clinical_insert ON public.imaging_orders
FOR INSERT TO authenticated
WITH CHECK (
  public.current_user_is_clinical_staff()
  AND requested_by=(SELECT auth.uid())
);

DROP POLICY IF EXISTS imaging_orders_clinical_read ON public.imaging_orders;
CREATE POLICY imaging_orders_clinical_read ON public.imaging_orders
FOR SELECT TO authenticated
USING (
  public.current_user_is_clinical_staff()
  OR patient_id=(SELECT auth.uid())
);

DROP POLICY IF EXISTS lab_orders_clinical_insert ON public.lab_orders;
CREATE POLICY lab_orders_clinical_insert ON public.lab_orders
FOR INSERT TO authenticated
WITH CHECK (
  public.current_user_is_clinical_staff()
  AND requested_by=(SELECT auth.uid())
);

DROP POLICY IF EXISTS lab_orders_clinical_read ON public.lab_orders;
CREATE POLICY lab_orders_clinical_read ON public.lab_orders
FOR SELECT TO authenticated
USING (
  public.current_user_is_clinical_staff()
  OR patient_id=(SELECT auth.uid())
);

DROP POLICY IF EXISTS staff_read_lab_tests ON public.lab_tests;
CREATE POLICY staff_read_lab_tests ON public.lab_tests
FOR SELECT TO authenticated
USING (public.current_user_is_clinical_staff());

DROP POLICY IF EXISTS mo_staff_delete ON public.meal_orders;
CREATE POLICY mo_staff_delete ON public.meal_orders
FOR DELETE TO authenticated
USING (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('canteen')
);

DROP POLICY IF EXISTS mo_staff_insert ON public.meal_orders;
CREATE POLICY mo_staff_insert ON public.meal_orders
FOR INSERT TO authenticated
WITH CHECK (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('canteen')
);

DROP POLICY IF EXISTS mo_staff_update ON public.meal_orders;
CREATE POLICY mo_staff_update ON public.meal_orders
FOR UPDATE TO authenticated
USING (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('canteen')
)
WITH CHECK (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('canteen')
);

DROP POLICY IF EXISTS mp_staff_delete ON public.meal_plans;
CREATE POLICY mp_staff_delete ON public.meal_plans
FOR DELETE TO authenticated
USING (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('canteen')
);

DROP POLICY IF EXISTS mp_staff_insert ON public.meal_plans;
CREATE POLICY mp_staff_insert ON public.meal_plans
FOR INSERT TO authenticated
WITH CHECK (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('canteen')
);

DROP POLICY IF EXISTS mp_staff_update ON public.meal_plans;
CREATE POLICY mp_staff_update ON public.meal_plans
FOR UPDATE TO authenticated
USING (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('canteen')
)
WITH CHECK (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('canteen')
);

DROP POLICY IF EXISTS nq_staff_delete ON public.notification_queue;
CREATE POLICY nq_staff_delete ON public.notification_queue
FOR DELETE TO authenticated
USING (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('admin')
);

DROP POLICY IF EXISTS nq_staff_insert ON public.notification_queue;
CREATE POLICY nq_staff_insert ON public.notification_queue
FOR INSERT TO authenticated
WITH CHECK (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('admin')
);

DROP POLICY IF EXISTS nq_staff_read ON public.notification_queue;
CREATE POLICY nq_staff_read ON public.notification_queue
FOR SELECT TO authenticated
USING (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('admin')
);

DROP POLICY IF EXISTS nq_staff_update ON public.notification_queue;
CREATE POLICY nq_staff_update ON public.notification_queue
FOR UPDATE TO authenticated
USING (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('admin')
)
WITH CHECK (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('admin')
);

DROP POLICY IF EXISTS staff_read_patient_audit ON public.patient_audit_log;
CREATE POLICY staff_read_patient_audit ON public.patient_audit_log
FOR SELECT TO authenticated
USING (
  public.current_user_is_clinical_staff()
  OR public.current_user_has_role('admin')
);

DROP POLICY IF EXISTS staff_read_visit_authorizations ON public.patient_visit_authorizations;
CREATE POLICY staff_read_visit_authorizations ON public.patient_visit_authorizations
FOR SELECT TO authenticated
USING (
  public.current_user_has_role('admin')
  OR public.current_user_has_role('accountant')
  OR public.current_user_has_role('front_desk')
  OR public.current_user_is_clinical_staff()
  OR EXISTS (
    SELECT 1 FROM public.patients p
    WHERE p.id=patient_visit_authorizations.patient_id
      AND p.user_id=(SELECT auth.uid())
  )
);

DROP POLICY IF EXISTS staff_read_service_order_events ON public.service_order_events;
CREATE POLICY staff_read_service_order_events ON public.service_order_events
FOR SELECT TO authenticated
USING (
  public.current_user_has_role('admin')
  OR public.current_user_has_role('accountant')
  OR public.current_user_is_clinical_staff()
);

DROP POLICY IF EXISTS service_orders_staff_read ON public.service_orders;
CREATE POLICY service_orders_staff_read ON public.service_orders
FOR SELECT TO authenticated
USING (
  public.current_user_has_role('admin')
  OR public.current_user_has_role('accountant')
  OR public.current_user_has_role('front_desk')
  OR public.current_user_is_clinical_staff()
);

DROP POLICY IF EXISTS tt_clinical_delete ON public.treatment_templates;
CREATE POLICY tt_clinical_delete ON public.treatment_templates
FOR DELETE TO authenticated
USING (public.current_user_is_clinical_staff());

DROP POLICY IF EXISTS tt_clinical_insert ON public.treatment_templates;
CREATE POLICY tt_clinical_insert ON public.treatment_templates
FOR INSERT TO authenticated
WITH CHECK (public.current_user_is_clinical_staff());

DROP POLICY IF EXISTS tt_clinical_read ON public.treatment_templates;
CREATE POLICY tt_clinical_read ON public.treatment_templates
FOR SELECT TO authenticated
USING (public.current_user_is_clinical_staff());

DROP POLICY IF EXISTS tt_clinical_update ON public.treatment_templates;
CREATE POLICY tt_clinical_update ON public.treatment_templates
FOR UPDATE TO authenticated
USING (public.current_user_is_clinical_staff())
WITH CHECK (public.current_user_is_clinical_staff());

DROP POLICY IF EXISTS va_clinical_all ON public.vital_alerts;
CREATE POLICY va_clinical_all ON public.vital_alerts
FOR ALL TO authenticated
USING (public.current_user_is_clinical_staff())
WITH CHECK (public.current_user_is_clinical_staff());
