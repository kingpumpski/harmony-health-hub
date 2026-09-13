-- Controlled performance/RLS reconciliation.
-- Preserves authorization semantics while making protected policies explicitly
-- authenticated, caching stable auth decisions per statement, and indexing
-- uncovered foreign keys.

CREATE OR REPLACE FUNCTION public.current_user_has_role(_role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT auth.uid()) IS NOT NULL, false)
     AND EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = (SELECT auth.uid()) AND role = _role);
$$;

CREATE OR REPLACE FUNCTION public.current_user_is_clinical_staff()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT auth.uid()) IS NOT NULL, false)
     AND EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = (SELECT auth.uid())
       AND role IN ('admin','practitioner','nurse','midwife','lab_technician','pharmacist','front_desk'));
$$;

CREATE OR REPLACE FUNCTION public.current_user_can_edit_patient_record()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT auth.uid()) IS NOT NULL, false)
     AND EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = (SELECT auth.uid())
       AND role IN ('admin','practitioner','nurse','midwife','front_desk'));
$$;

REVOKE ALL ON FUNCTION public.current_user_has_role(public.app_role) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_user_is_clinical_staff() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.current_user_can_edit_patient_record() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_has_role(public.app_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_is_clinical_staff() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_can_edit_patient_record() TO authenticated;

DO $$
DECLARE p record; q text; w text; role_clause text;
BEGIN
  FOR p IN SELECT tablename, policyname, roles, cmd, qual, with_check FROM pg_policies
    WHERE schemaname='public' AND ('public'=ANY(roles) OR coalesce(qual,'') LIKE '%auth.uid()%' OR coalesce(with_check,'') LIKE '%auth.uid()%') LOOP
    q := p.qual; w := p.with_check;
    IF q IS NOT NULL THEN
      q := replace(q, 'is_clinical_staff(auth.uid())', '(select public.current_user_is_clinical_staff())');
      q := replace(q, 'can_edit_patient_record(auth.uid())', '(select public.current_user_can_edit_patient_record())');
      q := regexp_replace(q, 'has_role\\(auth\\.uid\\(\\), ([^\\)]+)\\)', '(select public.current_user_has_role(\\1))', 'g');
      q := replace(q, 'auth.uid()', '(select auth.uid())'); q := replace(q, 'specialist_nurse', 'nurse');
    END IF;
    IF w IS NOT NULL THEN
      w := replace(w, 'is_clinical_staff(auth.uid())', '(select public.current_user_is_clinical_staff())');
      w := replace(w, 'can_edit_patient_record(auth.uid())', '(select public.current_user_can_edit_patient_record())');
      w := regexp_replace(w, 'has_role\\(auth\\.uid\\(\\), ([^\\)]+)\\)', '(select public.current_user_has_role(\\1))', 'g');
      w := replace(w, 'auth.uid()', '(select auth.uid())'); w := replace(w, 'specialist_nurse', 'nurse');
    END IF;
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', p.policyname, p.tablename);
    role_clause := CASE WHEN 'public'=ANY(p.roles) THEN 'authenticated' ELSE array_to_string(p.roles, ', ') END;
    IF p.cmd='ALL' THEN
      EXECUTE format('CREATE POLICY %I ON public.%I AS PERMISSIVE FOR ALL TO %s USING (%s) WITH CHECK (%s)', p.policyname,p.tablename,role_clause,q,coalesce(w,q));
    ELSIF p.cmd='INSERT' THEN
      EXECUTE format('CREATE POLICY %I ON public.%I AS PERMISSIVE FOR INSERT TO %s WITH CHECK (%s)', p.policyname,p.tablename,role_clause,w);
    ELSE
      EXECUTE format('CREATE POLICY %I ON public.%I AS PERMISSIVE FOR %s TO %s USING (%s)%s', p.policyname,p.tablename,p.cmd,role_clause,q,CASE WHEN p.cmd='UPDATE' AND w IS NOT NULL THEN format(' WITH CHECK (%s)',w) ELSE '' END);
    END IF;
  END LOOP;
END $$;

DROP POLICY IF EXISTS "clinical staff create triage" ON public.triage_assessments;
CREATE POLICY "clinical staff create triage" ON public.triage_assessments AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((select public.current_user_is_clinical_staff()) OR (select public.current_user_has_role('nurse'::public.app_role))) AND recorded_by=(select auth.uid()));
DROP POLICY IF EXISTS "clinical staff read triage" ON public.triage_assessments;
CREATE POLICY "clinical staff read triage" ON public.triage_assessments AS PERMISSIVE FOR SELECT TO authenticated
  USING ((select public.current_user_is_clinical_staff()) OR (select public.current_user_has_role('nurse'::public.app_role)) OR (select public.current_user_has_role('admin'::public.app_role)));

DROP INDEX IF EXISTS public.idx_triage_patient_time;

CREATE INDEX IF NOT EXISTS idx_admissions_admitting_practitioner_id ON public.admissions (admitting_practitioner);
CREATE INDEX IF NOT EXISTS idx_admissions_created_by ON public.admissions (created_by);
CREATE INDEX IF NOT EXISTS idx_appointments_practitioner_id ON public.appointments (practitioner_id);
CREATE INDEX IF NOT EXISTS idx_billing_item_payments_invoice_item_id ON public.billing_item_payments (invoice_item_id);
CREATE INDEX IF NOT EXISTS idx_billing_item_payments_payment_id ON public.billing_item_payments (payment_id);
CREATE INDEX IF NOT EXISTS idx_encounters_practitioner_id ON public.encounters (practitioner_id);
CREATE INDEX IF NOT EXISTS idx_fertility_cycles_assigned_specialist ON public.fertility_cycles (assigned_specialist);
CREATE INDEX IF NOT EXISTS idx_fertility_cycles_patient_id ON public.fertility_cycles (patient_id);
CREATE INDEX IF NOT EXISTS idx_fertility_monitoring_cycle_id ON public.fertility_monitoring (cycle_id);
CREATE INDEX IF NOT EXISTS idx_fertility_monitoring_recorded_by ON public.fertility_monitoring (recorded_by);
CREATE INDEX IF NOT EXISTS idx_insurance_claims_invoice_id ON public.insurance_claims (invoice_id);
CREATE INDEX IF NOT EXISTS idx_insurance_claims_patient_id ON public.insurance_claims (patient_id);
CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice_id ON public.invoice_items (invoice_id);
CREATE INDEX IF NOT EXISTS idx_invoices_created_by ON public.invoices (created_by);
CREATE INDEX IF NOT EXISTS idx_invoices_encounter_id ON public.invoices (encounter_id);
CREATE INDEX IF NOT EXISTS idx_invoices_patient_id ON public.invoices (patient_id);
CREATE INDEX IF NOT EXISTS idx_lab_orders_collected_by ON public.lab_orders (collected_by);
CREATE INDEX IF NOT EXISTS idx_lab_orders_encounter_id ON public.lab_orders (encounter_id);
CREATE INDEX IF NOT EXISTS idx_lab_orders_ordered_by ON public.lab_orders (ordered_by);
CREATE INDEX IF NOT EXISTS idx_lab_orders_patient_id ON public.lab_orders (patient_id);
CREATE INDEX IF NOT EXISTS idx_lab_results_approved_by ON public.lab_results (approved_by);
CREATE INDEX IF NOT EXISTS idx_lab_results_entered_by ON public.lab_results (entered_by);
CREATE INDEX IF NOT EXISTS idx_lab_results_lab_order_id ON public.lab_results (lab_order_id);
CREATE INDEX IF NOT EXISTS idx_patient_documents_uploaded_by ON public.patient_documents (uploaded_by);
CREATE INDEX IF NOT EXISTS idx_patients_created_by ON public.patients (created_by);
CREATE INDEX IF NOT EXISTS idx_payments_invoice_id ON public.payments (invoice_id);
CREATE INDEX IF NOT EXISTS idx_payments_patient_id ON public.payments (patient_id);
CREATE INDEX IF NOT EXISTS idx_payments_received_by ON public.payments (received_by);
CREATE INDEX IF NOT EXISTS idx_prescriptions_dispensed_by ON public.prescriptions (dispensed_by);
CREATE INDEX IF NOT EXISTS idx_prescriptions_encounter_id ON public.prescriptions (encounter_id);
CREATE INDEX IF NOT EXISTS idx_prescriptions_patient_id ON public.prescriptions (patient_id);
CREATE INDEX IF NOT EXISTS idx_prescriptions_prescribed_by ON public.prescriptions (prescribed_by);
CREATE INDEX IF NOT EXISTS idx_service_orders_created_by ON public.service_orders (created_by);
CREATE INDEX IF NOT EXISTS idx_service_orders_invoice_id ON public.service_orders (invoice_id);
CREATE INDEX IF NOT EXISTS idx_service_orders_invoice_item_id ON public.service_orders (invoice_item_id);
CREATE INDEX IF NOT EXISTS idx_service_orders_requested_by ON public.service_orders (requested_by);
CREATE INDEX IF NOT EXISTS idx_triage_assessments_recorded_by ON public.triage_assessments (recorded_by);
CREATE INDEX IF NOT EXISTS idx_video_sessions_appointment_id ON public.video_sessions (appointment_id);
CREATE INDEX IF NOT EXISTS idx_video_sessions_patient_id ON public.video_sessions (patient_id);
CREATE INDEX IF NOT EXISTS idx_video_sessions_practitioner_id ON public.video_sessions (practitioner_id);
CREATE INDEX IF NOT EXISTS idx_vital_signs_appointment_id ON public.vital_signs (appointment_id);
CREATE INDEX IF NOT EXISTS idx_vital_signs_patient_id ON public.vital_signs (patient_id);
CREATE INDEX IF NOT EXISTS idx_vital_signs_recorded_by ON public.vital_signs (recorded_by);

NOTIFY pgrst,'reload schema';