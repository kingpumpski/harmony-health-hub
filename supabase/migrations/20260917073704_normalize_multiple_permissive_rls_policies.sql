begin;

-- Convert broad ALL policies into explicit write commands so SELECT access is
-- represented by the dedicated read policy only. USING/WITH CHECK semantics
-- are preserved for UPDATE and DELETE/INSERT respectively.

DROP POLICY IF EXISTS ap_admin_write ON public.ai_protocols;
CREATE POLICY ap_admin_insert ON public.ai_protocols FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'practitioner'::app_role));
CREATE POLICY ap_admin_update ON public.ai_protocols FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'practitioner'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'practitioner'::app_role));
CREATE POLICY ap_admin_delete ON public.ai_protocols FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'practitioner'::app_role));

DROP POLICY IF EXISTS admins_write_symptom_map ON public.ai_symptom_icd_map;
CREATE POLICY admins_write_symptom_map_insert ON public.ai_symptom_icd_map FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY admins_write_symptom_map_update ON public.ai_symptom_icd_map FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY admins_write_symptom_map_delete ON public.ai_symptom_icd_map FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS aa_staff_all ON public.anesthetic_assessments;
CREATE POLICY aa_staff_insert ON public.anesthetic_assessments FOR INSERT TO authenticated WITH CHECK (is_clinical_staff((SELECT auth.uid())));
CREATE POLICY aa_staff_update ON public.anesthetic_assessments FOR UPDATE TO authenticated USING (is_clinical_staff((SELECT auth.uid()))) WITH CHECK (is_clinical_staff((SELECT auth.uid())));
CREATE POLICY aa_staff_delete ON public.anesthetic_assessments FOR DELETE TO authenticated USING (is_clinical_staff((SELECT auth.uid())));

DROP POLICY IF EXISTS "clinical operations manage" ON public.beds;
CREATE POLICY "clinical operations insert" ON public.beds FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'nurse'::app_role));
CREATE POLICY "clinical operations update" ON public.beds FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'nurse'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'nurse'::app_role));
CREATE POLICY "clinical operations delete" ON public.beds FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'nurse'::app_role));

DROP POLICY IF EXISTS "facility configuration admin manage" ON public.facility_configuration;
CREATE POLICY "facility configuration admin insert" ON public.facility_configuration FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY "facility configuration admin update" ON public.facility_configuration FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY "facility configuration admin delete" ON public.facility_configuration FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS config_admin_write ON public.facility_report_config;
CREATE POLICY config_admin_insert ON public.facility_report_config FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY config_admin_update ON public.facility_report_config FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY config_admin_delete ON public.facility_report_config FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS "facility settings admin manage" ON public.facility_settings;
CREATE POLICY "facility settings admin insert" ON public.facility_settings FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY "facility settings admin update" ON public.facility_settings FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY "facility settings admin delete" ON public.facility_settings FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS icd_admin_write ON public.icd_codes;
CREATE POLICY icd_admin_insert ON public.icd_codes FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY icd_admin_update ON public.icd_codes FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY icd_admin_delete ON public.icd_codes FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS lab_and_admin_manage_catalog ON public.lab_test_catalog;
CREATE POLICY lab_catalog_insert ON public.lab_test_catalog FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'lab_technician'::app_role));
CREATE POLICY lab_catalog_update ON public.lab_test_catalog FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'lab_technician'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'lab_technician'::app_role));
CREATE POLICY lab_catalog_delete ON public.lab_test_catalog FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'lab_technician'::app_role));

DROP POLICY IF EXISTS admins_manage_lab_catalogue ON public.lab_test_catalogue;
CREATE POLICY lab_catalogue_insert ON public.lab_test_catalogue FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY lab_catalogue_update ON public.lab_test_catalogue FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY lab_catalogue_delete ON public.lab_test_catalogue FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS lab_and_admin_manage_params ON public.lab_test_parameters;
CREATE POLICY lab_params_insert ON public.lab_test_parameters FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'lab_technician'::app_role));
CREATE POLICY lab_params_update ON public.lab_test_parameters FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'lab_technician'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'lab_technician'::app_role));
CREATE POLICY lab_params_delete ON public.lab_test_parameters FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'lab_technician'::app_role));

DROP POLICY IF EXISTS admins_write_lab_tests ON public.lab_tests;
CREATE POLICY lab_tests_insert ON public.lab_tests FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY lab_tests_update ON public.lab_tests FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY lab_tests_delete ON public.lab_tests FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS "maternity clinical write" ON public.maternity_episodes;
CREATE POLICY "maternity clinical insert" ON public.maternity_episodes FOR INSERT TO authenticated WITH CHECK ((created_by = (SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY "maternity clinical update" ON public.maternity_episodes FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'practitioner'::app_role) OR has_role((SELECT auth.uid()), 'nurse'::app_role) OR has_role((SELECT auth.uid()), 'midwife'::app_role)) WITH CHECK ((created_by = (SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY "maternity clinical delete" ON public.maternity_episodes FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'practitioner'::app_role) OR has_role((SELECT auth.uid()), 'nurse'::app_role) OR has_role((SELECT auth.uid()), 'midwife'::app_role));

DROP POLICY IF EXISTS "maternity observations clinical write" ON public.maternity_observations;
CREATE POLICY "maternity observations insert" ON public.maternity_observations FOR INSERT TO authenticated WITH CHECK ((recorded_by = (SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY "maternity observations update" ON public.maternity_observations FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'practitioner'::app_role) OR has_role((SELECT auth.uid()), 'nurse'::app_role) OR has_role((SELECT auth.uid()), 'midwife'::app_role)) WITH CHECK ((recorded_by = (SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY "maternity observations delete" ON public.maternity_observations FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role) OR has_role((SELECT auth.uid()), 'practitioner'::app_role) OR has_role((SELECT auth.uid()), 'nurse'::app_role) OR has_role((SELECT auth.uid()), 'midwife'::app_role));

DROP POLICY IF EXISTS mo_staff_all ON public.meal_orders;
CREATE POLICY mo_staff_insert ON public.meal_orders FOR INSERT TO authenticated WITH CHECK (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'canteen'::app_role));
CREATE POLICY mo_staff_update ON public.meal_orders FOR UPDATE TO authenticated USING (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'canteen'::app_role)) WITH CHECK (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'canteen'::app_role));
CREATE POLICY mo_staff_delete ON public.meal_orders FOR DELETE TO authenticated USING (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'canteen'::app_role));

DROP POLICY IF EXISTS mp_staff_all ON public.meal_plans;
CREATE POLICY mp_staff_insert ON public.meal_plans FOR INSERT TO authenticated WITH CHECK (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'canteen'::app_role));
CREATE POLICY mp_staff_update ON public.meal_plans FOR UPDATE TO authenticated USING (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'canteen'::app_role)) WITH CHECK (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'canteen'::app_role));
CREATE POLICY mp_staff_delete ON public.meal_plans FOR DELETE TO authenticated USING (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'canteen'::app_role));

DROP POLICY IF EXISTS nq_staff_write ON public.notification_queue;
CREATE POLICY nq_staff_insert ON public.notification_queue FOR INSERT TO authenticated WITH CHECK (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY nq_staff_update ON public.notification_queue FOR UPDATE TO authenticated USING (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'admin'::app_role)) WITH CHECK (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY nq_staff_delete ON public.notification_queue FOR DELETE TO authenticated USING (is_clinical_staff((SELECT auth.uid())) OR has_role((SELECT auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS gr_pharma_write ON public.pharmacy_goods_receipts;
CREATE POLICY gr_pharma_insert ON public.pharmacy_goods_receipts FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'pharmacist'::app_role) OR has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY gr_pharma_update ON public.pharmacy_goods_receipts FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'pharmacist'::app_role) OR has_role((SELECT auth.uid()), 'admin'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'pharmacist'::app_role) OR has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY gr_pharma_delete ON public.pharmacy_goods_receipts FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'pharmacist'::app_role) OR has_role((SELECT auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS inv_pharma_write ON public.pharmacy_inventory;
CREATE POLICY inv_pharma_insert ON public.pharmacy_inventory FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'pharmacist'::app_role) OR has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY inv_pharma_update ON public.pharmacy_inventory FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'pharmacist'::app_role) OR has_role((SELECT auth.uid()), 'admin'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'pharmacist'::app_role) OR has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY inv_pharma_delete ON public.pharmacy_inventory FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'pharmacist'::app_role) OR has_role((SELECT auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS stg_admin_write ON public.stg_guidelines;
CREATE POLICY stg_admin_insert ON public.stg_guidelines FOR INSERT TO authenticated WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY stg_admin_update ON public.stg_guidelines FOR UPDATE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role)) WITH CHECK (has_role((SELECT auth.uid()), 'admin'::app_role));
CREATE POLICY stg_admin_delete ON public.stg_guidelines FOR DELETE TO authenticated USING (has_role((SELECT auth.uid()), 'admin'::app_role));

DROP POLICY IF EXISTS tt_clinical_write ON public.treatment_templates;
CREATE POLICY tt_clinical_insert ON public.treatment_templates FOR INSERT TO authenticated WITH CHECK (is_clinical_staff((SELECT auth.uid())));
CREATE POLICY tt_clinical_update ON public.treatment_templates FOR UPDATE TO authenticated USING (is_clinical_staff((SELECT auth.uid()))) WITH CHECK (is_clinical_staff((SELECT auth.uid())));
CREATE POLICY tt_clinical_delete ON public.treatment_templates FOR DELETE TO authenticated USING (is_clinical_staff((SELECT auth.uid())));

commit;
