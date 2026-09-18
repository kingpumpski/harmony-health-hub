SELECT 1;
-- Idempotent production RPC compatibility hotfix.
CREATE OR REPLACE FUNCTION public.create_admission_workflow(_patient_id UUID, _ward TEXT, _bed TEXT DEFAULT NULL, _reason TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Admission creation is not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF _ward IS NULL OR btrim(_ward)='' THEN RAISE EXCEPTION 'Ward is required'; END IF;
  INSERT INTO public.admissions(patient_id,ward,bed,reason,admitted_by,status,admitted_at) VALUES (_patient_id,btrim(_ward),NULLIF(btrim(_bed),''),NULLIF(btrim(_reason),''),auth.uid(),'admitted',now()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('admission_id',v_id,'status','admitted');
END; $$;

CREATE OR REPLACE FUNCTION public.get_missing_billing_tariffs(_patient_id UUID DEFAULT NULL)
RETURNS TABLE(invoice_item_id UUID,invoice_id UUID,patient_id UUID,description TEXT,department TEXT,service_code TEXT,quantity INTEGER,unit_price NUMERIC,amount NUMERIC,service_order_id UUID,service_order_status TEXT,created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Billing access denied'; END IF;
  RETURN QUERY SELECT ii.id,ii.invoice_id,i.patient_id,ii.description,ii.department,ii.service_code,ii.quantity,ii.unit_price,ii.amount,so.id,so.status,ii.created_at
  FROM public.invoice_items ii JOIN public.invoices i ON i.id=ii.invoice_id
  LEFT JOIN LATERAL (SELECT s.id,s.status FROM public.service_orders s WHERE s.invoice_item_id=ii.id AND s.status<>'cancelled' ORDER BY s.created_at DESC LIMIT 1) so ON true
  WHERE ii.amount<=0 AND ii.unit_price<=0 AND i.status IN ('pending','partially_paid') AND (_patient_id IS NULL OR i.patient_id=_patient_id) ORDER BY ii.created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.grant_service_order_override(_service_order_id UUID,_reason TEXT)
RETURNS public.billing_overrides LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_order public.service_orders; v_override public.billing_overrides;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant')) THEN RAISE EXCEPTION 'Only Accounts staff can grant billing overrides'; END IF;
  IF length(trim(COALESCE(_reason,'')))<3 THEN RAISE EXCEPTION 'An override reason of at least 3 characters is required'; END IF;
  SELECT * INTO v_order FROM public.service_orders WHERE id=_service_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service order not found'; END IF;
  IF v_order.status<>'pending_payment_approval' THEN RAISE EXCEPTION 'Billing override is only available before service release'; END IF;
  INSERT INTO public.billing_overrides(service_order_id,patient_id,department,related_entity_id,reason,overridden_by,approved_by,approved_at)
  VALUES(v_order.id,v_order.patient_id,v_order.department,v_order.related_entity_id,trim(_reason),auth.uid(),auth.uid(),now())
  ON CONFLICT(service_order_id) DO UPDATE SET patient_id=EXCLUDED.patient_id,department=EXCLUDED.department,related_entity_id=EXCLUDED.related_entity_id,reason=EXCLUDED.reason,overridden_by=EXCLUDED.overridden_by,approved_by=EXCLUDED.approved_by,approved_at=EXCLUDED.approved_at
  RETURNING * INTO v_override;
  RETURN v_override;
END; $$;

CREATE OR REPLACE FUNCTION public.release_service_order(_service_order_id UUID,_reason TEXT DEFAULT 'Payment received')
RETURNS public.service_orders LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_order public.service_orders; v_paid NUMERIC(12,2):=0; v_override BOOLEAN:=false; v_encounter_status TEXT;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Accounts release permission required'; END IF;
  SELECT * INTO v_order FROM public.service_orders WHERE id=_service_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Service order not found'; END IF;
  IF v_order.encounter_id IS NOT NULL THEN
    SELECT status INTO v_encounter_status FROM public.encounters WHERE id=v_order.encounter_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Linked encounter not found'; END IF;
    IF v_encounter_status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Cannot release a service order linked to a completed or cancelled encounter'; END IF;
  END IF;
  IF v_order.status<>'pending_payment_approval' THEN RETURN v_order; END IF;
  SELECT COALESCE(SUM(p.amount),0) INTO v_paid FROM public.payments p WHERE p.invoice_id=v_order.invoice_id AND (p.paid_at IS NOT NULL OR lower(COALESCE(p.status,'')) IN ('paid','completed','confirmed','success','successful'));
  SELECT EXISTS(SELECT 1 FROM public.billing_overrides b WHERE b.service_order_id=v_order.id) INTO v_override;
  IF v_order.payment_required AND v_order.amount>0 AND (v_order.invoice_id IS NULL OR v_paid<v_order.amount) AND NOT v_override THEN RAISE EXCEPTION 'Payment approval is required before release'; END IF;
  UPDATE public.service_orders SET status='released',approved_at=now(),approved_by=auth.uid(),updated_at=now() WHERE id=v_order.id AND status='pending_payment_approval' RETURNING * INTO v_order;
  INSERT INTO public.department_queues(service_order_id,patient_id,department,related_encounter_id,related_invoice_id,payment_required,payment_satisfied,priority,reason,created_by,queued_at,status)
  VALUES(v_order.id,v_order.patient_id,v_order.department,v_order.encounter_id,v_order.invoice_id,v_order.payment_required,true,'normal',v_order.service_name,auth.uid(),now(),'queued')
  ON CONFLICT(service_order_id) DO UPDATE SET payment_satisfied=true,status=CASE WHEN public.department_queues.status='cancelled' THEN 'queued' ELSE public.department_queues.status END,updated_at=now();
  IF v_order.order_type='imaging' AND v_order.related_entity_id IS NOT NULL THEN UPDATE public.imaging_orders SET status='released',updated_at=now() WHERE id=v_order.related_entity_id AND service_order_id=v_order.id AND status='pending_payment_approval'; END IF;
  RETURN v_order;
END; $$;

CREATE OR REPLACE FUNCTION public.enter_lab_result(_lab_order_id UUID,_result_text TEXT,_numeric_value NUMERIC DEFAULT NULL,_interpretation TEXT DEFAULT NULL,_is_abnormal BOOLEAN DEFAULT false)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID:=auth.uid(); v_order public.lab_orders%ROWTYPE; v_catalog public.lab_test_catalogue%ROWTYPE; v_result UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;
  IF NOT (public.is_clinical_staff(v_uid) OR public.has_role(v_uid,'admin')) THEN RAISE EXCEPTION 'Clinical staff access required'; END IF;
  SELECT * INTO v_order FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF v_order.status<>'sample_collected' THEN RAISE EXCEPTION 'Sample must be collected before result entry'; END IF;
  IF _result_text IS NULL OR btrim(_result_text)='' THEN RAISE EXCEPTION 'Result value is required'; END IF;
  IF v_order.lab_test_catalogue_id IS NOT NULL THEN SELECT * INTO v_catalog FROM public.lab_test_catalogue WHERE id=v_order.lab_test_catalogue_id; END IF;
  INSERT INTO public.lab_results(lab_order_id,result_data,interpretation,is_abnormal,entered_by,status,numeric_value,unit,reference_low,reference_high,abnormal_flag)
  VALUES(_lab_order_id,jsonb_build_object('value',_result_text),_interpretation,_is_abnormal,v_uid,'completed',_numeric_value,v_catalog.unit,v_catalog.reference_low,v_catalog.reference_high,CASE WHEN _is_abnormal THEN 'abnormal' ELSE 'normal' END) RETURNING id INTO v_result;
  UPDATE public.lab_orders SET status='completed',updated_at=now() WHERE id=_lab_order_id;
  RETURN v_result;
END; $$;

REVOKE ALL ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.get_missing_billing_tariffs(UUID) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.grant_service_order_override(UUID,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.release_service_order(UUID,TEXT) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_admission_workflow(UUID,TEXT,TEXT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_missing_billing_tariffs(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.grant_service_order_override(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_service_order(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enter_lab_result(UUID,TEXT,NUMERIC,TEXT,BOOLEAN) TO authenticated;
NOTIFY pgrst,'reload schema';


-- Database-backed permission catalog and role mapping.
-- UI permission filtering is additive; existing RPC/RLS role checks remain authoritative.

CREATE TABLE IF NOT EXISTS public.permissions (
  permission_key TEXT PRIMARY KEY,
  description TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.role_permissions (
  role public.app_role NOT NULL,
  permission_key TEXT NOT NULL REFERENCES public.permissions(permission_key) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (role, permission_key)
);

ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.permissions TO authenticated;
GRANT SELECT ON public.role_permissions TO authenticated;
GRANT ALL ON public.permissions TO service_role;
GRANT ALL ON public.role_permissions TO service_role;

DROP POLICY IF EXISTS permissions_authenticated_read ON public.permissions;
CREATE POLICY permissions_authenticated_read ON public.permissions FOR SELECT TO authenticated USING (is_active OR public.has_role(auth.uid(),'admin'));

DROP POLICY IF EXISTS permissions_admin_insert ON public.permissions;
CREATE POLICY permissions_admin_insert ON public.permissions FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS permissions_admin_update ON public.permissions;
CREATE POLICY permissions_admin_update ON public.permissions FOR UPDATE TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS permissions_admin_delete ON public.permissions;
CREATE POLICY permissions_admin_delete ON public.permissions FOR DELETE TO authenticated USING (public.has_role(auth.uid(),'admin'));

DROP POLICY IF EXISTS role_permissions_read_own ON public.role_permissions;
CREATE POLICY role_permissions_read_own ON public.role_permissions FOR SELECT TO authenticated
USING (role IN (SELECT ur.role FROM public.user_roles ur WHERE ur.user_id=auth.uid()) OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS role_permissions_admin_insert ON public.role_permissions;
CREATE POLICY role_permissions_admin_insert ON public.role_permissions FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS role_permissions_admin_update ON public.role_permissions;
CREATE POLICY role_permissions_admin_update ON public.role_permissions FOR UPDATE TO authenticated USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS role_permissions_admin_delete ON public.role_permissions;
CREATE POLICY role_permissions_admin_delete ON public.role_permissions FOR DELETE TO authenticated USING (public.has_role(auth.uid(),'admin'));

INSERT INTO public.permissions(permission_key,description)
VALUES ('dashboard','Harmony Health Hub dashboard navigation capability'),('patients','Harmony Health Hub patients navigation capability'),('registration','Harmony Health Hub registration navigation capability'),('appointments','Harmony Health Hub appointments navigation capability'),('triage','Harmony Health Hub triage navigation capability'),('encounters','Harmony Health Hub encounters navigation capability'),('clinical_operations','Harmony Health Hub clinical operations navigation capability'),('ward','Harmony Health Hub ward navigation capability'),('handover','Harmony Health Hub handover navigation capability'),('emergency','Harmony Health Hub emergency navigation capability'),('theatre','Harmony Health Hub theatre navigation capability'),('transfusion','Harmony Health Hub transfusion navigation capability'),('claims','Harmony Health Hub claims navigation capability'),('reports','Harmony Health Hub reports navigation capability'),('report_submissions','Harmony Health Hub report submissions navigation capability'),('accounts_approvals','Harmony Health Hub accounts approvals navigation capability'),('tariff_adjustments','Harmony Health Hub tariff adjustments navigation capability'),('department_queue','Harmony Health Hub department queue navigation capability'),('laboratory','Harmony Health Hub laboratory navigation capability'),('radiology','Harmony Health Hub radiology navigation capability'),('radiology_results','Harmony Health Hub radiology results navigation capability'),('pharmacy','Harmony Health Hub pharmacy navigation capability'),('medication_administration','Harmony Health Hub medication administration navigation capability'),('billing','Harmony Health Hub billing navigation capability'),('maternity','Harmony Health Hub maternity navigation capability'),('telemedicine','Harmony Health Hub telemedicine navigation capability'),('fertility','Harmony Health Hub fertility navigation capability'),('dental','Harmony Health Hub dental navigation capability'),('procedures','Harmony Health Hub procedures navigation capability'),('anesthesia','Harmony Health Hub anesthesia navigation capability'),('ophthalmology','Harmony Health Hub ophthalmology navigation capability'),('ai_clinical','Harmony Health Hub ai clinical navigation capability'),('users','Harmony Health Hub users navigation capability'),('system_library','Harmony Health Hub system library navigation capability'),('offline_sync','Harmony Health Hub offline sync navigation capability'),('data_import','Harmony Health Hub data import navigation capability'),('inpatients','Harmony Health Hub inpatients navigation capability'),('meal_orders','Harmony Health Hub meal orders navigation capability'),('notifications','Harmony Health Hub notifications navigation capability'),('outside_lab','Harmony Health Hub outside lab navigation capability'),('financial_reports','Harmony Health Hub financial reports navigation capability'),('inventory','Harmony Health Hub inventory navigation capability'),('stock_alerts','Harmony Health Hub stock alerts navigation capability'),('patient_portal','Harmony Health Hub patient portal navigation capability'),('orders','Harmony Health Hub orders navigation capability'),('dietary_plans','Harmony Health Hub dietary plans navigation capability')
ON CONFLICT(permission_key) DO UPDATE SET description=EXCLUDED.description;

INSERT INTO public.role_permissions(role,permission_key)
VALUES
  ('admin','dashboard'),
  ('admin','patients'),
  ('admin','registration'),
  ('admin','appointments'),
  ('admin','triage'),
  ('admin','encounters'),
  ('admin','clinical_operations'),
  ('admin','ward'),
  ('admin','handover'),
  ('admin','emergency'),
  ('admin','theatre'),
  ('admin','transfusion'),
  ('admin','claims'),
  ('admin','reports'),
  ('admin','report_submissions'),
  ('admin','accounts_approvals'),
  ('admin','tariff_adjustments'),
  ('admin','department_queue'),
  ('admin','laboratory'),
  ('admin','radiology'),
  ('admin','radiology_results'),
  ('admin','pharmacy'),
  ('admin','medication_administration'),
  ('admin','billing'),
  ('admin','maternity'),
  ('admin','telemedicine'),
  ('admin','fertility'),
  ('admin','dental'),
  ('admin','procedures'),
  ('admin','anesthesia'),
  ('admin','ophthalmology'),
  ('admin','ai_clinical'),
  ('admin','users'),
  ('admin','system_library'),
  ('admin','offline_sync'),
  ('admin','data_import'),
  ('admin','inpatients'),
  ('admin','meal_orders'),
  ('admin','notifications'),
  ('admin','outside_lab'),
  ('admin','financial_reports'),
  ('admin','inventory'),
  ('admin','stock_alerts'),
  ('admin','patient_portal'),
  ('admin','orders'),
  ('admin','dietary_plans'),
  ('practitioner','dashboard'),
  ('practitioner','appointments'),
  ('practitioner','patients'),
  ('practitioner','encounters'),
  ('practitioner','clinical_operations'),
  ('practitioner','emergency'),
  ('practitioner','theatre'),
  ('practitioner','transfusion'),
  ('practitioner','department_queue'),
  ('practitioner','radiology'),
  ('practitioner','radiology_results'),
  ('practitioner','dental'),
  ('practitioner','procedures'),
  ('practitioner','anesthesia'),
  ('practitioner','laboratory'),
  ('practitioner','pharmacy'),
  ('practitioner','medication_administration'),
  ('practitioner','telemedicine'),
  ('practitioner','fertility'),
  ('practitioner','ophthalmology'),
  ('practitioner','ai_clinical'),
  ('nurse','dashboard'),
  ('nurse','patients'),
  ('nurse','triage'),
  ('nurse','encounters'),
  ('nurse','clinical_operations'),
  ('nurse','ward'),
  ('nurse','handover'),
  ('nurse','emergency'),
  ('nurse','theatre'),
  ('nurse','transfusion'),
  ('nurse','inpatients'),
  ('nurse','medication_administration'),
  ('nurse','meal_orders'),
  ('specialist_nurse','dashboard'),
  ('specialist_nurse','patients'),
  ('specialist_nurse','appointments'),
  ('specialist_nurse','triage'),
  ('specialist_nurse','encounters'),
  ('specialist_nurse','clinical_operations'),
  ('specialist_nurse','ward'),
  ('specialist_nurse','handover'),
  ('specialist_nurse','emergency'),
  ('specialist_nurse','theatre'),
  ('specialist_nurse','transfusion'),
  ('specialist_nurse','inpatients'),
  ('specialist_nurse','medication_administration'),
  ('specialist_nurse','ai_clinical'),
  ('midwife','dashboard'),
  ('midwife','maternity'),
  ('midwife','fertility'),
  ('midwife','inpatients'),
  ('midwife','clinical_operations'),
  ('midwife','handover'),
  ('midwife','emergency'),
  ('midwife','theatre'),
  ('midwife','transfusion'),
  ('midwife','triage'),
  ('midwife','medication_administration'),
  ('radiologist','dashboard'),
  ('radiologist','radiology'),
  ('radiologist','department_queue'),
  ('radiologist','patients'),
  ('radiologist','notifications'),
  ('radiologist','ai_clinical'),
  ('front_desk','dashboard'),
  ('front_desk','patients'),
  ('front_desk','registration'),
  ('front_desk','appointments'),
  ('front_desk','triage'),
  ('front_desk','clinical_operations'),
  ('front_desk','billing'),
  ('accountant','dashboard'),
  ('accountant','billing'),
  ('accountant','tariff_adjustments'),
  ('accountant','claims'),
  ('accountant','accounts_approvals'),
  ('accountant','clinical_operations'),
  ('accountant','financial_reports'),
  ('lab_technician','dashboard'),
  ('lab_technician','department_queue'),
  ('lab_technician','laboratory'),
  ('lab_technician','outside_lab'),
  ('lab_technician','reports'),
  ('pharmacist','dashboard'),
  ('pharmacist','department_queue'),
  ('pharmacist','pharmacy'),
  ('pharmacist','medication_administration'),
  ('pharmacist','inventory'),
  ('pharmacist','stock_alerts'),
  ('canteen','dashboard'),
  ('canteen','meal_orders'),
  ('canteen','orders'),
  ('canteen','dietary_plans'),
  ('patient','dashboard'),
  ('patient','patient_portal'),
  ('patient','appointments'),
  ('patient','telemedicine'),
  ('patient','billing')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.get_my_permissions()
RETURNS TABLE(permission_key TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public
AS $$
  SELECT rp.permission_key
  FROM public.role_permissions rp
  JOIN public.permissions p ON p.permission_key=rp.permission_key
  JOIN public.user_roles ur ON ur.role=rp.role
  WHERE ur.user_id=auth.uid() AND p.is_active
  ORDER BY rp.permission_key;
$$;

REVOKE ALL ON FUNCTION public.get_my_permissions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_permissions() TO authenticated;


-- Transactional administrator role-permission replacement.
CREATE OR REPLACE FUNCTION public.replace_role_permissions(
  _role public.app_role,
  _permission_keys TEXT[]
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF _permission_keys IS NULL THEN
    RAISE EXCEPTION 'Permission list is required';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(_permission_keys) requested(permission_key)
    LEFT JOIN public.permissions p ON p.permission_key=requested.permission_key AND p.is_active
    WHERE p.permission_key IS NULL
  ) THEN
    RAISE EXCEPTION 'One or more requested permissions are invalid or inactive';
  END IF;
  DELETE FROM public.role_permissions WHERE role=_role;
  INSERT INTO public.role_permissions(role,permission_key)
  SELECT _role, permission_key FROM unnest(_permission_keys) AS requested(permission_key)
  ON CONFLICT DO NOTHING;
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION public.replace_role_permissions(public.app_role,TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_role_permissions(public.app_role,TEXT[]) TO authenticated;


-- Functional-domain permissions compatibility hotfix.
INSERT INTO public.permissions(permission_key,description,is_active)
VALUES ('inpatient','Inpatient functional domain: admissions, movements, beds, handover and ward operations'),('finance','Finance functional domain: billing, approvals, claims and reconciliation'),('administration','Administration functional domain: users, permissions, settings, audit and system operations')
ON CONFLICT(permission_key) DO UPDATE SET description=EXCLUDED.description,is_active=TRUE;
INSERT INTO public.role_permissions(role,permission_key)
VALUES ('admin','inpatient'),('admin','finance'),('admin','administration'),('practitioner','inpatient'),('practitioner','reports'),('nurse','inpatient'),('specialist_nurse','inpatient'),('midwife','inpatient'),('accountant','finance'),('accountant','reports'),('front_desk','finance')
ON CONFLICT DO NOTHING;


-- Preserve administrator full-access invariant for onboarding/support.
CREATE OR REPLACE FUNCTION public.get_my_permissions()
RETURNS TABLE(permission_key TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT p.permission_key FROM public.permissions p WHERE p.is_active AND EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id=auth.uid() AND ur.role='admin')
  UNION
  SELECT rp.permission_key FROM public.role_permissions rp JOIN public.permissions p ON p.permission_key=rp.permission_key JOIN public.user_roles ur ON ur.role=rp.role
  WHERE ur.user_id=auth.uid() AND p.is_active AND NOT EXISTS (SELECT 1 FROM public.user_roles admin_check WHERE admin_check.user_id=auth.uid() AND admin_check.role='admin')
  ORDER BY permission_key;
$$;
REVOKE ALL ON FUNCTION public.get_my_permissions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_permissions() TO authenticated;

CREATE OR REPLACE FUNCTION public.replace_role_permissions(_role public.app_role,_permission_keys TEXT[])
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin') THEN RAISE EXCEPTION 'Administrator access required'; END IF;
  IF _permission_keys IS NULL THEN RAISE EXCEPTION 'Permission list is required'; END IF;
  IF _role='admin' THEN
    DELETE FROM public.role_permissions WHERE role='admin';
    INSERT INTO public.role_permissions(role,permission_key) SELECT 'admin',permission_key FROM public.permissions WHERE is_active ON CONFLICT DO NOTHING;
    RETURN TRUE;
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(_permission_keys) requested(permission_key) LEFT JOIN public.permissions p ON p.permission_key=requested.permission_key AND p.is_active WHERE p.permission_key IS NULL) THEN RAISE EXCEPTION 'One or more requested permissions are invalid or inactive'; END IF;
  DELETE FROM public.role_permissions WHERE role=_role;
  INSERT INTO public.role_permissions(role,permission_key) SELECT _role,permission_key FROM unnest(_permission_keys) AS requested(permission_key) ON CONFLICT DO NOTHING;
  RETURN TRUE;
END;
$$;
REVOKE ALL ON FUNCTION public.replace_role_permissions(public.app_role,TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.replace_role_permissions(public.app_role,TEXT[]) TO authenticated;


-- IT Admin support role compatibility hotfix.
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'it_admin';
INSERT INTO public.permissions(permission_key, description, is_active)
VALUES ('it_support','IT support domain: system diagnostics, audit visibility and offline synchronization support',TRUE)
ON CONFLICT(permission_key) DO UPDATE SET description=EXCLUDED.description, is_active=TRUE;
INSERT INTO public.role_permissions(role, permission_key)
VALUES ('it_admin','dashboard'),('it_admin','it_support'),('it_admin','notifications'),('it_admin','offline_sync')
ON CONFLICT DO NOTHING;
DROP POLICY IF EXISTS "system audit admin read" ON public.system_audit_log;
CREATE POLICY "system audit admin and it support read"
ON public.system_audit_log FOR SELECT TO authenticated
USING (public.has_role((SELECT auth.uid()),'admin'::public.app_role) OR public.has_role((SELECT auth.uid()),'it_admin'::public.app_role));
