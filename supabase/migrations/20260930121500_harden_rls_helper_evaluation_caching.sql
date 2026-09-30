-- Harden RLS policy helper evaluation for facility-scoped authorization.
-- Stable authorization helpers are evaluated once per statement rather than
-- once per candidate row, preserving authorization semantics while reducing
-- repeated helper execution on large datasets.

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'wards','beds','anesthetic_assessments','billing_overrides','dental_records',
    'inpatient_reviews','meal_orders','meal_plans','ophthalmology_exams',
    'outside_lab_documents','patient_account_credits','patient_visit_authorizations',
    'video_sessions'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS remaining_facility_select ON public.%I', t);
    EXECUTE format('CREATE POLICY remaining_facility_select ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING ((facility_id IS NOT NULL AND (select public.current_user_has_facility_access(facility_id))) OR (facility_id IS NULL AND ((select public.current_user_has_role(''admin''::public.app_role)) OR (select public.current_user_has_role(''it_admin''::public.app_role)))))', t);

    EXECUTE format('DROP POLICY IF EXISTS remaining_facility_insert ON public.%I', t);
    EXECUTE format('CREATE POLICY remaining_facility_insert ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (facility_id IS NOT NULL AND (select public.current_user_has_facility_access(facility_id)))', t);

    EXECUTE format('DROP POLICY IF EXISTS remaining_facility_update ON public.%I', t);
    EXECUTE format('CREATE POLICY remaining_facility_update ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated USING ((facility_id IS NOT NULL AND (select public.current_user_has_facility_access(facility_id))) OR (facility_id IS NULL AND ((select public.current_user_has_role(''admin''::public.app_role)) OR (select public.current_user_has_role(''it_admin''::public.app_role))))) WITH CHECK (facility_id IS NOT NULL AND (select public.current_user_has_facility_access(facility_id)))', t);

    EXECUTE format('DROP POLICY IF EXISTS remaining_facility_delete ON public.%I', t);
    EXECUTE format('CREATE POLICY remaining_facility_delete ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated USING (facility_id IS NOT NULL AND (select public.current_user_has_facility_access(facility_id)))', t);
  END LOOP;
END $$;

DROP POLICY IF EXISTS facility_data_sharing_agreements_read ON public.facility_data_sharing_agreements;
CREATE POLICY facility_data_sharing_agreements_read ON public.facility_data_sharing_agreements
FOR SELECT TO authenticated
USING (
  (select public.current_user_has_role('system_superuser'))
  OR facility_a_id = (select public.current_user_facility_id())
  OR facility_b_id = (select public.current_user_facility_id())
);

DROP POLICY IF EXISTS facility_data_sharing_agreement_scopes_read ON public.facility_data_sharing_agreement_scopes;
CREATE POLICY facility_data_sharing_agreement_scopes_read ON public.facility_data_sharing_agreement_scopes
FOR SELECT TO authenticated
USING (
  (select public.current_user_has_role('system_superuser'))
  OR EXISTS (
    SELECT 1 FROM public.facility_data_sharing_agreements a
    WHERE a.id = agreement_id
      AND (
        a.facility_a_id = (select public.current_user_facility_id())
        OR a.facility_b_id = (select public.current_user_facility_id())
      )
  )
);

DROP POLICY IF EXISTS memberships_read ON public.facility_memberships;
CREATE POLICY memberships_read ON public.facility_memberships
FOR SELECT TO authenticated
USING (
  user_id = (select auth.uid())
  OR (select public.current_user_has_role('system_superuser'))
  OR (
    (select public.current_user_has_role('admin'))
    AND facility_id = (select public.current_user_facility_id())
  )
);
