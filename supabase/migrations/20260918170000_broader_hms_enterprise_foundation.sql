-- Additive enterprise foundation for the broader HMS scope.
CREATE TABLE IF NOT EXISTS public.hms_module_catalog (
 module_id text PRIMARY KEY, module_code text UNIQUE NOT NULL, module_name text NOT NULL,
 category text NOT NULL, optional boolean NOT NULL DEFAULT false,
 safety_level text NOT NULL DEFAULT 'medium' CHECK (safety_level IN ('low','medium','high','critical')),
 default_enabled boolean NOT NULL DEFAULT false, description text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.hms_module_catalog(module_id,module_code,module_name,category,optional,safety_level,description) VALUES
('physiotherapy','M7','Physiotherapy','clinical',true,'high','Assessments and therapy sessions using canonical encounters/care plans'),
('dietary-restaurant','M13','Dietary & Nutrition','ancillary',true,'medium','Menus, therapeutic diets, meal orders and delivery'),
('teaching-research','M21','Teaching & Research','education',true,'high','Governed secondary-use teaching and research'),
('asset-biomedical','M24','Asset & Biomedical','enterprise',false,'high','Equipment ownership, maintenance and calibration'),
('procurement','M23-P','Procurement','enterprise',false,'high','Suppliers, purchase orders, approvals and receiving'),
('data-import','M17','Data Import','platform',false,'high','Versioned staging, validation, quarantine and reversible commit'),
('report-centre','M16','Report Centre','analytics',false,'high','Statutory, operational, clinical, financial and analytical reports'),
('user-role-management','M19','User & Role Management','governance',false,'critical','Enterprise role and permission governance')
ON CONFLICT(module_id) DO UPDATE SET module_name=excluded.module_name,description=excluded.description,updated_at=now();

CREATE TABLE IF NOT EXISTS public.hms_facility_modules (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL,
 module_id text NOT NULL REFERENCES public.hms_module_catalog(module_id), enabled boolean NOT NULL DEFAULT false,
 effective_from timestamptz NOT NULL DEFAULT now(), effective_to timestamptz, configured_by uuid, configured_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(facility_id,module_id)
);
ALTER TABLE public.hms_facility_modules ENABLE ROW LEVEL SECURITY;
CREATE POLICY hms_facility_modules_admin ON public.hms_facility_modules FOR ALL TO authenticated
 USING(public.has_role((SELECT auth.uid()),'admin'::public.app_role))
 WITH CHECK(public.has_role((SELECT auth.uid()),'admin'::public.app_role));
CREATE POLICY hms_facility_modules_service ON public.hms_facility_modules FOR ALL TO service_role USING(true) WITH CHECK(true);

CREATE OR REPLACE FUNCTION public.set_hms_facility_module(_facility_id uuid,_module_id text,_enabled boolean)
RETURNS public.hms_facility_modules LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r public.hms_facility_modules;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN RAISE EXCEPTION 'Administrator authorization required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.hms_module_catalog WHERE module_id=_module_id) THEN RAISE EXCEPTION 'Unknown HMS module'; END IF;
 INSERT INTO public.hms_facility_modules(facility_id,module_id,enabled,configured_by) VALUES(_facility_id,_module_id,_enabled,auth.uid())
 ON CONFLICT(facility_id,module_id) DO UPDATE SET enabled=excluded.enabled,effective_from=now(),effective_to=NULL,configured_by=auth.uid(),configured_at=now()
 RETURNING * INTO r; RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.set_hms_facility_module(uuid,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_hms_facility_module(uuid,text,boolean) TO authenticated;

CREATE TABLE IF NOT EXISTS public.hms_role_catalog (
 role_code text PRIMARY KEY, role_name text NOT NULL, group_code text NOT NULL,
 external_role boolean NOT NULL DEFAULT false, advisory_only boolean NOT NULL DEFAULT false,
 active boolean NOT NULL DEFAULT true, description text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.hms_role_catalog(role_code,role_name,group_code,external_role,advisory_only) VALUES
('super_admin','Super Admin','governance',false,false),('hospital_admin','Hospital Admin','governance',false,false),('medical_director','Medical Director','governance',false,false),('it_admin','IT Admin','governance',false,false),('dba','DBA','governance',false,false),('compliance','Compliance','governance',false,false),('facility_module_manager','Facility Module Manager','governance',false,false),
('doctor','Doctor','clinical',false,false),('specialist','Specialist','clinical',false,false),('surgeon','Surgeon','clinical',false,false),('nurse','Nurse','clinical',false,false),('midwife','Midwife','clinical',false,false),('pharmacist','Pharmacist','clinical',false,false),('lab_scientist','Lab Scientist','clinical',false,false),('radiologist','Radiologist','clinical',false,false),('physiotherapist','Physiotherapist','clinical',false,false),('fertility_specialist','Fertility Specialist','clinical',false,false),('dietitian','Dietitian','clinical',false,false),('anesthetist','Anesthetist','clinical',false,false),('triage_officer','Triage Officer','clinical',false,false),('ward_clerk','Ward Clerk','clinical',false,false),
('restaurant_manager','Restaurant Manager','restaurant',false,false),('chef','Chef','restaurant',false,false),('order_clerk','Order Clerk','restaurant',false,false),('attendant','Attendant','restaurant',false,false),('billing_clerk','Billing Clerk','restaurant',false,false),
('receptionist','Receptionist','support',false,false),('admissions_officer','Admissions Officer','support',false,false),('cashier','Cashier','support',false,false),('insurance_officer','Insurance Officer','support',false,false),('records_officer','Records Officer','support',false,false),('mortuary_officer','Mortuary Officer','support',false,false),('transport_officer','Transport Officer','support',false,false),('housekeeping','Housekeeping','support',false,false),('biomedical_engineer','Biomedical Engineer','support',false,false),('security_officer','Security Officer','support',false,false),
('report_centre_manager','Report Centre Manager','reporting',false,false),('statutory_officer','Statutory Officer','reporting',false,false),('bi_analyst','BI Analyst','reporting',false,false),('departmental_viewer','Departmental Viewer','reporting',false,false),
('ai_admin','AI Admin','ai',false,true),('specialist_ai','Specialist AI','ai',false,true),('clinical_ai_reviewer','Clinical AI Reviewer','ai',false,true),
('patient','Patient','external',true,false),('nok_delegate','NOK Delegate','external',true,false),('referral_doctor','Referral Doctor','external',true,false),('regulator','Regulator','external',true,false),('vendor','Vendor','external',true,false),
('lecturer','Lecturer','teaching',false,false),('student','Student','teaching',false,false),('supervisor','Supervisor','teaching',false,false),('researcher','Researcher','teaching',false,false)
ON CONFLICT(role_code) DO UPDATE SET role_name=excluded.role_name,group_code=excluded.group_code,updated_at=now();

CREATE TABLE IF NOT EXISTS public.hms_role_module_permissions (
 role_code text REFERENCES public.hms_role_catalog(role_code) ON DELETE CASCADE, module_code text NOT NULL,
 can_read boolean NOT NULL DEFAULT false, can_write boolean NOT NULL DEFAULT false, can_approve boolean NOT NULL DEFAULT false,
 can_configure boolean NOT NULL DEFAULT false, scope_code text NOT NULL DEFAULT 'none', PRIMARY KEY(role_code,module_code)
);
INSERT INTO public.hms_role_module_permissions(role_code,module_code)
SELECT r.role_code,m.module_code FROM public.hms_role_catalog r CROSS JOIN generate_series(1,25) n
CROSS JOIN LATERAL (SELECT 'M'||n::text AS module_code) m ON CONFLICT DO NOTHING;
ALTER TABLE public.hms_role_catalog ENABLE ROW LEVEL SECURITY; ALTER TABLE public.hms_role_module_permissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY hms_role_catalog_admin ON public.hms_role_catalog FOR ALL TO authenticated USING(public.has_role((SELECT auth.uid()),'admin'::public.app_role)) WITH CHECK(public.has_role((SELECT auth.uid()),'admin'::public.app_role));
CREATE POLICY hms_role_matrix_admin ON public.hms_role_module_permissions FOR ALL TO authenticated USING(public.has_role((SELECT auth.uid()),'admin'::public.app_role)) WITH CHECK(public.has_role((SELECT auth.uid()),'admin'::public.app_role));

CREATE TABLE IF NOT EXISTS public.hms_import_templates(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),code text UNIQUE NOT NULL,module_code text NOT NULL,entity_name text NOT NULL,import_type text NOT NULL CHECK(import_type IN('A','B','C','D')),current_version int NOT NULL DEFAULT 1,status text NOT NULL DEFAULT 'active',created_by uuid,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.hms_import_template_versions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),template_id uuid REFERENCES public.hms_import_templates(id) ON DELETE CASCADE,version_no int NOT NULL,schema_definition jsonb NOT NULL,mapping_definition jsonb NOT NULL DEFAULT '{}',rules_definition jsonb NOT NULL DEFAULT '{}',UNIQUE(template_id,version_no));
CREATE TABLE IF NOT EXISTS public.hms_import_batches(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),template_id uuid REFERENCES public.hms_import_templates(id),template_version int NOT NULL,status text NOT NULL DEFAULT 'uploaded',source_filename text,checksum text,row_count int NOT NULL DEFAULT 0,accepted_count int NOT NULL DEFAULT 0,rejected_count int NOT NULL DEFAULT 0,quarantine_count int NOT NULL DEFAULT 0,created_by uuid NOT NULL,approved_by uuid,committed_by uuid,created_at timestamptz NOT NULL DEFAULT now(),committed_at timestamptz,rollback_at timestamptz);
CREATE TABLE IF NOT EXISTS public.hms_import_staging(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),batch_id uuid REFERENCES public.hms_import_batches(id) ON DELETE CASCADE,row_number int NOT NULL,payload jsonb NOT NULL,normalized_payload jsonb,validation_status text NOT NULL DEFAULT 'pending',validation_errors jsonb NOT NULL DEFAULT '[]',UNIQUE(batch_id,row_number));
CREATE TABLE IF NOT EXISTS public.hms_import_errors(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),batch_id uuid REFERENCES public.hms_import_batches(id) ON DELETE CASCADE,staging_id uuid REFERENCES public.hms_import_staging(id) ON DELETE CASCADE,severity text NOT NULL,code text NOT NULL,message text NOT NULL,details jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.hms_import_quarantine(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),staging_id uuid REFERENCES public.hms_import_staging(id) ON DELETE CASCADE,resolution_status text NOT NULL DEFAULT 'open',resolution_note text,resolved_by uuid,resolved_at timestamptz);
CREATE TABLE IF NOT EXISTS public.hms_import_mappings(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),batch_id uuid REFERENCES public.hms_import_batches(id) ON DELETE CASCADE,source_field text NOT NULL,target_field text NOT NULL,transform_expression text,approved boolean NOT NULL DEFAULT false);
CREATE TABLE IF NOT EXISTS public.hms_import_audit(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),batch_id uuid REFERENCES public.hms_import_batches(id) ON DELETE CASCADE,action text NOT NULL,actor_id uuid,occurred_at timestamptz NOT NULL DEFAULT now(),details jsonb NOT NULL DEFAULT '{}');

CREATE TABLE IF NOT EXISTS public.hms_report_templates(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),code text UNIQUE NOT NULL,name text NOT NULL,category text NOT NULL,definition jsonb NOT NULL DEFAULT '{}',active boolean NOT NULL DEFAULT true,created_by uuid,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.hms_report_runs(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),template_id uuid REFERENCES public.hms_report_templates(id),period_start date,period_end date,status text NOT NULL DEFAULT 'queued',output_formats text[] NOT NULL DEFAULT ARRAY['csv'],output_uri text,requested_by uuid,started_at timestamptz,completed_at timestamptz,error_details jsonb);
CREATE TABLE IF NOT EXISTS public.hms_report_submissions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),report_run_id uuid REFERENCES public.hms_report_runs(id) ON DELETE CASCADE,authority_code text NOT NULL,status text NOT NULL DEFAULT 'draft',submission_reference text,submitted_by uuid,submitted_at timestamptz,response_details jsonb);

CREATE TABLE IF NOT EXISTS public.hms_procurement_suppliers(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),supplier_code text UNIQUE NOT NULL,name text NOT NULL,status text NOT NULL DEFAULT 'active',contact jsonb NOT NULL DEFAULT '{}',created_by uuid,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.hms_purchase_orders(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),supplier_id uuid REFERENCES public.hms_procurement_suppliers(id),po_number text UNIQUE NOT NULL,status text NOT NULL DEFAULT 'draft',currency_code text NOT NULL DEFAULT 'GHS',total_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK(total_amount>=0),requested_by uuid,approved_by uuid,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.hms_procurement_receipts(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),purchase_order_id uuid REFERENCES public.hms_purchase_orders(id),received_at timestamptz NOT NULL DEFAULT now(),received_by uuid NOT NULL,status text NOT NULL DEFAULT 'pending',reconciliation jsonb NOT NULL DEFAULT '{}');

CREATE TABLE IF NOT EXISTS public.hms_biomedical_assets(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),asset_tag text UNIQUE NOT NULL,asset_name text NOT NULL,asset_class text NOT NULL,manufacturer text,model text,serial_number text,facility_id uuid,location text,status text NOT NULL DEFAULT 'active',criticality text NOT NULL DEFAULT 'medium',purchase_date date,warranty_end date,next_calibration_at date,next_maintenance_at date,clinical_device_registry_id uuid,created_by uuid,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.hms_biomedical_maintenance(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),asset_id uuid REFERENCES public.hms_biomedical_assets(id) ON DELETE CASCADE,activity_type text NOT NULL,status text NOT NULL DEFAULT 'scheduled',scheduled_at timestamptz,completed_at timestamptz,performed_by uuid,notes text,evidence jsonb NOT NULL DEFAULT '{}');

CREATE TABLE IF NOT EXISTS public.hms_physio_assessments(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),patient_id uuid NOT NULL,encounter_id uuid,therapist_id uuid NOT NULL,assessment jsonb NOT NULL DEFAULT '{}',plan jsonb NOT NULL DEFAULT '{}',status text NOT NULL DEFAULT 'draft',created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.hms_physio_sessions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),assessment_id uuid REFERENCES public.hms_physio_assessments(id) ON DELETE CASCADE,session_at timestamptz NOT NULL DEFAULT now(),therapist_id uuid NOT NULL,intervention jsonb NOT NULL DEFAULT '{}',response jsonb NOT NULL DEFAULT '{}',status text NOT NULL DEFAULT 'planned');

CREATE TABLE IF NOT EXISTS public.hms_teaching_research_projects(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),project_code text UNIQUE NOT NULL,title text NOT NULL,project_type text NOT NULL,purpose text NOT NULL,status text NOT NULL DEFAULT 'draft',de_identified boolean NOT NULL DEFAULT true,retention_until date,approved_by uuid,created_by uuid,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS public.hms_teaching_research_dataset_requests(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),project_id uuid REFERENCES public.hms_teaching_research_projects(id) ON DELETE CASCADE,requested_by uuid NOT NULL,data_scope jsonb NOT NULL,purpose text NOT NULL,approval_status text NOT NULL DEFAULT 'pending',approved_by uuid,approved_at timestamptz,de_identification_method text,created_at timestamptz NOT NULL DEFAULT now());

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['hms_import_templates','hms_import_template_versions','hms_import_batches','hms_import_staging','hms_import_errors','hms_import_quarantine','hms_import_mappings','hms_import_audit','hms_report_templates','hms_report_runs','hms_report_submissions','hms_procurement_suppliers','hms_purchase_orders','hms_procurement_receipts','hms_biomedical_assets','hms_biomedical_maintenance','hms_physio_assessments','hms_physio_sessions','hms_teaching_research_projects','hms_teaching_research_dataset_requests'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',t||'_admin',t);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING(public.has_role((SELECT auth.uid()),''admin''::public.app_role)) WITH CHECK(public.has_role((SELECT auth.uid()),''admin''::public.app_role))',t||'_admin',t);
  EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',t||'_service',t);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO service_role USING(true) WITH CHECK(true)',t||'_service',t);
 END LOOP;
 IF to_regprocedure('public.audit_clinical_record_change()') IS NOT NULL THEN
  FOREACH t IN ARRAY ARRAY['hms_facility_modules','hms_role_catalog','hms_role_module_permissions','hms_import_templates','hms_import_template_versions','hms_import_batches','hms_import_staging','hms_import_errors','hms_import_quarantine','hms_import_mappings','hms_import_audit','hms_report_templates','hms_report_runs','hms_report_submissions','hms_procurement_suppliers','hms_purchase_orders','hms_procurement_receipts','hms_biomedical_assets','hms_biomedical_maintenance','hms_physio_assessments','hms_physio_sessions','hms_teaching_research_projects','hms_teaching_research_dataset_requests'] LOOP
   EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I','trg_hms_audit_'||t,t);
   EXECUTE format('CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.audit_clinical_record_change()','trg_hms_audit_'||t,t);
  END LOOP;
 END IF;
END $$;
