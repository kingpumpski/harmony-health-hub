-- Complete remaining facility attribution for patient-linked and facility-structural transactions.
-- Historical NULLs remain reviewable only to administrators/IT administrators.

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['wards','beds','anesthetic_assessments','billing_overrides','dental_records','inpatient_reviews','meal_orders','meal_plans','ophthalmology_exams','outside_lab_documents','patient_account_credits','patient_visit_authorizations','video_sessions'] LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS facility_id uuid REFERENCES public.healthcare_facilities(id)',t);
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I(facility_id)',t||'_facility_id_idx',t);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.enforce_remaining_facility_lineage()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_active uuid:=public.current_user_facility_id(); v_parent uuid;
BEGIN
  IF TG_TABLE_NAME='wards' THEN
    IF NEW.facility_id IS NULL THEN NEW.facility_id:=v_active; END IF;
  ELSIF TG_TABLE_NAME='beds' THEN
    SELECT facility_id INTO v_parent FROM public.wards WHERE id=NEW.ward_id;
    IF v_parent IS NULL AND NEW.admission_id IS NOT NULL THEN SELECT facility_id INTO v_parent FROM public.admissions WHERE id=NEW.admission_id; END IF;
    IF v_parent IS NULL AND NEW.patient_id IS NOT NULL THEN SELECT facility_id INTO v_parent FROM public.patients WHERE id=NEW.patient_id; END IF;
    IF NEW.facility_id IS NULL THEN NEW.facility_id:=coalesce(v_parent,v_active); END IF;
  ELSIF TG_TABLE_NAME IN ('anesthetic_assessments','dental_records') THEN
    IF NEW.encounter_id IS NOT NULL THEN SELECT facility_id INTO v_parent FROM public.encounters WHERE id=NEW.encounter_id; END IF;
    IF v_parent IS NULL AND NEW.patient_id IS NOT NULL THEN SELECT facility_id INTO v_parent FROM public.patients WHERE id=NEW.patient_id; END IF;
    IF NEW.facility_id IS NULL THEN NEW.facility_id:=coalesce(v_parent,v_active); END IF;
  ELSIF TG_TABLE_NAME='inpatient_reviews' THEN
    SELECT facility_id INTO v_parent FROM public.admissions WHERE id=NEW.admission_id;
    IF v_parent IS NULL THEN SELECT facility_id INTO v_parent FROM public.patients WHERE id=NEW.patient_id; END IF;
    IF NEW.facility_id IS NULL THEN NEW.facility_id:=coalesce(v_parent,v_active); END IF;
  ELSIF TG_TABLE_NAME='billing_overrides' THEN
    IF NEW.service_order_id IS NOT NULL THEN SELECT facility_id INTO v_parent FROM public.service_orders WHERE id=NEW.service_order_id; END IF;
    IF v_parent IS NULL THEN SELECT facility_id INTO v_parent FROM public.patients WHERE id=NEW.patient_id; END IF;
    IF NEW.facility_id IS NULL THEN NEW.facility_id:=coalesce(v_parent,v_active); END IF;
  ELSIF TG_TABLE_NAME='meal_orders' THEN
    IF NEW.meal_plan_id IS NOT NULL THEN SELECT facility_id INTO v_parent FROM public.meal_plans WHERE id=NEW.meal_plan_id; END IF;
    IF v_parent IS NULL THEN SELECT facility_id INTO v_parent FROM public.patients WHERE id=NEW.patient_id; END IF;
    IF NEW.facility_id IS NULL THEN NEW.facility_id:=coalesce(v_parent,v_active); END IF;
  ELSIF TG_TABLE_NAME IN ('meal_plans','ophthalmology_exams','outside_lab_documents','patient_account_credits','patient_visit_authorizations') THEN
    SELECT facility_id INTO v_parent FROM public.patients WHERE id=NEW.patient_id;
    IF NEW.facility_id IS NULL THEN NEW.facility_id:=coalesce(v_parent,v_active); END IF;
  ELSIF TG_TABLE_NAME='video_sessions' THEN
    IF NEW.appointment_id IS NOT NULL THEN SELECT facility_id INTO v_parent FROM public.appointments WHERE id=NEW.appointment_id; END IF;
    IF v_parent IS NULL AND NEW.service_order_id IS NOT NULL THEN SELECT facility_id INTO v_parent FROM public.service_orders WHERE id=NEW.service_order_id; END IF;
    IF v_parent IS NULL THEN SELECT facility_id INTO v_parent FROM public.patients WHERE id=NEW.patient_id; END IF;
    IF NEW.facility_id IS NULL THEN NEW.facility_id:=coalesce(v_parent,v_active); END IF;
  END IF;
  IF NEW.facility_id IS NULL THEN RAISE EXCEPTION 'Facility attribution is required for %',TG_TABLE_NAME USING ERRCODE='23514'; END IF;
  IF v_parent IS NOT NULL AND NEW.facility_id IS DISTINCT FROM v_parent THEN RAISE EXCEPTION 'Facility lineage mismatch for %',TG_TABLE_NAME USING ERRCODE='42501'; END IF;
  IF v_active IS NOT NULL AND NEW.facility_id IS DISTINCT FROM v_active AND NOT (public.current_user_has_role('admin'::public.app_role) OR public.current_user_has_role('it_admin'::public.app_role)) THEN RAISE EXCEPTION 'Active facility mismatch for %',TG_TABLE_NAME USING ERRCODE='42501'; END IF;
  IF TG_OP='UPDATE' AND OLD.facility_id IS NOT NULL AND NEW.facility_id IS NULL THEN RAISE EXCEPTION 'Facility attribution cannot be cleared for %',TG_TABLE_NAME USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.enforce_remaining_facility_lineage() FROM PUBLIC,anon,authenticated;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['wards','beds','anesthetic_assessments','billing_overrides','dental_records','inpatient_reviews','meal_orders','meal_plans','ophthalmology_exams','outside_lab_documents','patient_account_credits','patient_visit_authorizations','video_sessions'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS enforce_remaining_facility_lineage ON public.%I',t);
    EXECUTE format('CREATE TRIGGER enforce_remaining_facility_lineage BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.enforce_remaining_facility_lineage()',t);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
    EXECUTE format('DROP POLICY IF EXISTS remaining_facility_select ON public.%I',t);
    EXECUTE format('CREATE POLICY remaining_facility_select ON public.%I AS RESTRICTIVE FOR SELECT TO authenticated USING ((facility_id IS NOT NULL AND (select public.current_user_has_facility_access(facility_id))) OR (facility_id IS NULL AND ((select public.current_user_has_role(''admin''::public.app_role)) OR (select public.current_user_has_role(''it_admin''::public.app_role)))))',t);
    EXECUTE format('DROP POLICY IF EXISTS remaining_facility_insert ON public.%I',t);
    EXECUTE format('CREATE POLICY remaining_facility_insert ON public.%I AS RESTRICTIVE FOR INSERT TO authenticated WITH CHECK (facility_id IS NOT NULL AND (select public.current_user_has_facility_access(facility_id)))',t);
    EXECUTE format('DROP POLICY IF EXISTS remaining_facility_update ON public.%I',t);
    EXECUTE format('CREATE POLICY remaining_facility_update ON public.%I AS RESTRICTIVE FOR UPDATE TO authenticated USING ((facility_id IS NOT NULL AND (select public.current_user_has_facility_access(facility_id))) OR (facility_id IS NULL AND ((select public.current_user_has_role(''admin''::public.app_role)) OR (select public.current_user_has_role(''it_admin''::public.app_role))))) WITH CHECK (facility_id IS NOT NULL AND (select public.current_user_has_facility_access(facility_id)))',t);
    EXECUTE format('DROP POLICY IF EXISTS remaining_facility_delete ON public.%I',t);
    EXECUTE format('CREATE POLICY remaining_facility_delete ON public.%I AS RESTRICTIVE FOR DELETE TO authenticated USING (facility_id IS NOT NULL AND (select public.current_user_has_facility_access(facility_id)))',t);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.list_unresolved_remaining_clinical_facility_records(_limit integer DEFAULT 500)
RETURNS TABLE(entity_type text,entity_id uuid,patient_id uuid,created_at timestamptz,metadata jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
BEGIN
 IF NOT (public.current_user_has_role('admin'::public.app_role) OR public.current_user_has_role('it_admin'::public.app_role)) THEN RAISE EXCEPTION 'Administrator access required'; END IF;
 RETURN QUERY
 SELECT 'wards',w.id,NULL::uuid,w.created_at,jsonb_build_object('name',w.name,'ward_type',w.ward_type) FROM public.wards w WHERE w.facility_id IS NULL
 UNION ALL SELECT 'beds',b.id,b.patient_id,b.created_at,jsonb_build_object('bed_number',b.bed_number,'ward_id',b.ward_id) FROM public.beds b WHERE b.facility_id IS NULL
 UNION ALL SELECT 'anesthetic_assessments',a.id,a.patient_id,a.created_at,jsonb_build_object('status',a.status,'encounter_id',a.encounter_id) FROM public.anesthetic_assessments a WHERE a.facility_id IS NULL
 UNION ALL SELECT 'billing_overrides',b.id,b.patient_id,b.created_at,jsonb_build_object('department',b.department,'reason',b.reason,'service_order_id',b.service_order_id) FROM public.billing_overrides b WHERE b.facility_id IS NULL
 UNION ALL SELECT 'dental_records',d.id,d.patient_id,d.created_at,jsonb_build_object('encounter_id',d.encounter_id) FROM public.dental_records d WHERE d.facility_id IS NULL
 UNION ALL SELECT 'inpatient_reviews',i.id,i.patient_id,i.created_at,jsonb_build_object('admission_id',i.admission_id,'review_type',i.review_type) FROM public.inpatient_reviews i WHERE i.facility_id IS NULL
 UNION ALL SELECT 'meal_orders',m.id,m.patient_id,m.created_at,jsonb_build_object('meal_plan_id',m.meal_plan_id,'meal_type',m.meal_type,'status',m.status) FROM public.meal_orders m WHERE m.facility_id IS NULL
 UNION ALL SELECT 'meal_plans',m.id,m.patient_id,m.created_at,jsonb_build_object('plan_type',m.plan_type,'active',m.active) FROM public.meal_plans m WHERE m.facility_id IS NULL
 UNION ALL SELECT 'ophthalmology_exams',o.id,o.patient_id,o.created_at,jsonb_build_object('status',o.status,'performed_by',o.performed_by) FROM public.ophthalmology_exams o WHERE o.facility_id IS NULL
 UNION ALL SELECT 'outside_lab_documents',o.id,o.patient_id,o.created_at,jsonb_build_object('document_type',o.document_type,'title',o.title) FROM public.outside_lab_documents o WHERE o.facility_id IS NULL
 UNION ALL SELECT 'patient_account_credits',p.id,p.patient_id,p.created_at,jsonb_build_object('entry_type',p.entry_type,'amount',p.amount,'invoice_id',p.invoice_id) FROM public.patient_account_credits p WHERE p.facility_id IS NULL
 UNION ALL SELECT 'patient_visit_authorizations',p.id,p.patient_id,p.created_at,jsonb_build_object('payer_name',p.payer_name,'coverage_type',p.coverage_type,'appointment_id',p.appointment_id) FROM public.patient_visit_authorizations p WHERE p.facility_id IS NULL
 UNION ALL SELECT 'video_sessions',v.id,v.patient_id,v.created_at,jsonb_build_object('appointment_id',v.appointment_id,'service_order_id',v.service_order_id,'status',v.status) FROM public.video_sessions v WHERE v.facility_id IS NULL
 LIMIT greatest(1,least(coalesce(_limit,500),1000));
END $$;
REVOKE ALL ON FUNCTION public.list_unresolved_remaining_clinical_facility_records(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.list_unresolved_remaining_clinical_facility_records(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.reconcile_remaining_clinical_facility_record(_entity_type text,_entity_id uuid,_target_facility_id uuid,_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_patient uuid; v_parent uuid;
BEGIN
 IF NOT (public.current_user_has_role('admin'::public.app_role) OR public.current_user_has_role('it_admin'::public.app_role)) THEN RAISE EXCEPTION 'Administrator access required'; END IF;
 IF _reason IS NULL OR length(trim(_reason))<5 THEN RAISE EXCEPTION 'Evidence/reason is required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.healthcare_facilities f WHERE f.id=_target_facility_id AND f.is_active) THEN RAISE EXCEPTION 'Target facility is not active'; END IF;
 IF _entity_type='wards' THEN PERFORM 1 FROM public.wards WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='beds' THEN SELECT patient_id INTO v_patient FROM public.beds WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='anesthetic_assessments' THEN SELECT patient_id INTO v_patient FROM public.anesthetic_assessments WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='billing_overrides' THEN SELECT patient_id INTO v_patient FROM public.billing_overrides WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='dental_records' THEN SELECT patient_id INTO v_patient FROM public.dental_records WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='inpatient_reviews' THEN SELECT patient_id INTO v_patient FROM public.inpatient_reviews WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='meal_orders' THEN SELECT patient_id INTO v_patient FROM public.meal_orders WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='meal_plans' THEN SELECT patient_id INTO v_patient FROM public.meal_plans WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='ophthalmology_exams' THEN SELECT patient_id INTO v_patient FROM public.ophthalmology_exams WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='outside_lab_documents' THEN SELECT patient_id INTO v_patient FROM public.outside_lab_documents WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='patient_account_credits' THEN SELECT patient_id INTO v_patient FROM public.patient_account_credits WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='patient_visit_authorizations' THEN SELECT patient_id INTO v_patient FROM public.patient_visit_authorizations WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSIF _entity_type='video_sessions' THEN SELECT patient_id INTO v_patient FROM public.video_sessions WHERE id=_entity_id AND facility_id IS NULL FOR UPDATE;
 ELSE RAISE EXCEPTION 'Unsupported facility reconciliation entity'; END IF;
 IF v_patient IS NOT NULL THEN SELECT facility_id INTO v_parent FROM public.patients WHERE id=v_patient; IF v_parent IS NOT NULL AND v_parent IS DISTINCT FROM _target_facility_id THEN RAISE EXCEPTION 'Patient facility conflicts with target facility'; END IF; END IF;
 PERFORM set_config('hms.facility_reconciliation','on',true);
 CASE _entity_type
  WHEN 'wards' THEN UPDATE public.wards SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'beds' THEN UPDATE public.beds SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'anesthetic_assessments' THEN UPDATE public.anesthetic_assessments SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'billing_overrides' THEN UPDATE public.billing_overrides SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'dental_records' THEN UPDATE public.dental_records SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'inpatient_reviews' THEN UPDATE public.inpatient_reviews SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'meal_orders' THEN UPDATE public.meal_orders SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'meal_plans' THEN UPDATE public.meal_plans SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'ophthalmology_exams' THEN UPDATE public.ophthalmology_exams SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'outside_lab_documents' THEN UPDATE public.outside_lab_documents SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'patient_account_credits' THEN UPDATE public.patient_account_credits SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'patient_visit_authorizations' THEN UPDATE public.patient_visit_authorizations SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
  WHEN 'video_sessions' THEN UPDATE public.video_sessions SET facility_id=_target_facility_id WHERE id=_entity_id AND facility_id IS NULL;
 END CASE;
 PERFORM public.record_system_audit('facility_reconciliation',auth.uid(),jsonb_build_object('entity_type',_entity_type,'entity_id',_entity_id,'target_facility_id',_target_facility_id,'reason',trim(_reason)));
END $$;
REVOKE ALL ON FUNCTION public.reconcile_remaining_clinical_facility_record(text,uuid,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reconcile_remaining_clinical_facility_record(text,uuid,uuid,text) TO authenticated;
