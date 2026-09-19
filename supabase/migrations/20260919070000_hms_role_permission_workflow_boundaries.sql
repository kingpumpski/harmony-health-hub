-- Next-generation HMS role/permission convergence.
-- The existing public.user_roles + app_role remains the authority for who a user is.
-- hms_role_catalog / hms_role_module_permissions remain configuration metadata.
-- private.hms_authorize is the only bridge between the two; no second user-assignment RBAC is introduced.

CREATE SCHEMA IF NOT EXISTS private;

CREATE TABLE IF NOT EXISTS public.hms_app_role_map (
  app_role text PRIMARY KEY,
  role_code text NOT NULL REFERENCES public.hms_role_catalog(role_code) ON DELETE RESTRICT,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.hms_app_role_map(app_role,role_code)
VALUES
  ('admin','super_admin'),
  ('practitioner','doctor'),
  ('nurse','nurse'),
  ('midwife','midwife'),
  ('specialist_nurse','nurse'),
  ('lab_technician','lab_scientist'),
  ('pharmacist','pharmacist'),
  ('accountant','billing_clerk'),
  ('front_desk','receptionist'),
  ('canteen','restaurant_manager'),
  ('patient','patient')
ON CONFLICT(app_role) DO UPDATE
SET role_code=excluded.role_code,active=true,updated_at=now();

ALTER TABLE public.hms_app_role_map ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS hms_app_role_map_admin ON public.hms_app_role_map;
CREATE POLICY hms_app_role_map_admin ON public.hms_app_role_map
  FOR ALL TO authenticated
  USING(public.has_role((SELECT auth.uid()),'admin'::public.app_role))
  WITH CHECK(public.has_role((SELECT auth.uid()),'admin'::public.app_role));
DROP POLICY IF EXISTS hms_app_role_map_service ON public.hms_app_role_map;
CREATE POLICY hms_app_role_map_service ON public.hms_app_role_map
  FOR ALL TO service_role USING(true) WITH CHECK(true);

-- Ensure the broader modules have a stable module-code representation in the
-- existing permission matrix. Existing codes remain canonical.
INSERT INTO public.hms_module_catalog(module_id,module_code,module_name,category,optional,safety_level,default_enabled,description)
VALUES
  ('physiotherapy','M7','Physiotherapy','clinical',true,'high',false,'Assessments and therapy sessions using canonical encounters/care plans'),
  ('dietary-restaurant','M13','Dietary & Nutrition','ancillary',true,'medium',false,'Menus, therapeutic diets, meal orders and delivery'),
  ('teaching-research','M21','Teaching & Research','education',true,'high',false,'Governed secondary-use teaching and research'),
  ('asset-biomedical','M24','Asset & Biomedical','enterprise',false,'high',true,'Equipment ownership, maintenance and calibration'),
  ('procurement','M23-P','Procurement','enterprise',false,'high',true,'Suppliers, purchase orders, approvals and receiving'),
  ('data-import','M17','Data Import','platform',false,'high',true,'Versioned staging, validation, quarantine and reversible commit'),
  ('report-centre','M16','Report Centre','analytics',false,'high',true,'Statutory, operational, clinical, financial and analytical reports'),
  ('user-role-management','M19','User & Role Management','governance',false,'critical',true,'Enterprise role and permission governance')
ON CONFLICT(module_id) DO UPDATE
SET module_code=excluded.module_code,module_name=excluded.module_name,updated_at=now();

-- The original foundation seeded M1..M25. Add explicit rows for any
-- module-code that was introduced by the broader catalog and then seed a
-- conservative least-privilege baseline for legacy application roles.
INSERT INTO public.hms_role_module_permissions(role_code,module_code)
SELECT r.role_code,m.module_code
FROM public.hms_role_catalog r
CROSS JOIN public.hms_module_catalog m
ON CONFLICT DO NOTHING;

-- Administrator retains full platform access; this is an invariant, not a UI toggle.
UPDATE public.hms_role_module_permissions
SET can_read=true,can_write=true,can_approve=true,can_configure=true,scope_code='global'
WHERE role_code='super_admin';

-- Safe operational defaults for the legacy roles. Administrators may extend
-- these through the existing role/module matrix before enabling production.
WITH grants(role_code,module_code,can_read,can_write,can_approve,can_configure,scope_code) AS (
  VALUES
    ('doctor','report-centre',true,false,false,false,'facility'),
    ('nurse','report-centre',true,false,false,false,'facility'),
    ('midwife','report-centre',true,false,false,false,'facility'),
    ('lab_scientist','report-centre',true,false,false,false,'facility'),
    ('pharmacist','report-centre',true,false,false,false,'facility'),
    ('billing_clerk','report-centre',true,true,true,false,'facility'),
    ('receptionist','report-centre',true,false,false,false,'facility'),
    ('restaurant_manager','dietary-restaurant',true,true,true,false,'facility')
)
INSERT INTO public.hms_role_module_permissions(role_code,module_code,can_read,can_write,can_approve,can_configure,scope_code)
SELECT * FROM grants
ON CONFLICT(role_code,module_code) DO UPDATE
SET can_read=EXCLUDED.can_read,
    can_write=EXCLUDED.can_write,
    can_approve=EXCLUDED.can_approve,
    can_configure=EXCLUDED.can_configure,
    scope_code=EXCLUDED.scope_code;

CREATE OR REPLACE FUNCTION private.hms_authorize(
  _user_id uuid,
  _facility_id uuid,
  _module_id text,
  _action text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=''
AS $$
  SELECT
    _user_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.user_roles ur
      JOIN public.hms_app_role_map arm
        ON arm.app_role=ur.role::text
       AND arm.active=true
      JOIN public.hms_role_module_permissions p
        ON p.role_code=arm.role_code
      JOIN public.hms_module_catalog mc
        ON mc.module_code=p.module_code
      WHERE ur.user_id=_user_id
        AND mc.module_id=_module_id
        AND p.scope_code IN ('facility','global')
        AND public.hms_module_is_enabled(_facility_id,_module_id)
        AND (
          (lower(_action)='read' AND p.can_read)
          OR (lower(_action)='write' AND p.can_write)
          OR (lower(_action)='approve' AND p.can_approve)
          OR (lower(_action)='configure' AND p.can_configure)
        )
    );
$$;

REVOKE ALL ON FUNCTION private.hms_authorize(uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.hms_authorize(uuid,uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.hms_has_permission(
  _facility_id uuid,
  _module_id text,
  _action text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path=''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  IF lower(_action) NOT IN ('read','write','approve','configure') THEN
    RETURN false;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.hms_module_catalog WHERE module_id=_module_id
  ) THEN
    RETURN false;
  END IF;
  IF public.has_role(auth.uid(),'admin'::public.app_role) THEN
    RETURN public.hms_module_is_enabled(_facility_id,_module_id);
  END IF;
  RETURN private.hms_authorize(auth.uid(),_facility_id,_module_id,_action);
END;
$$;

CREATE OR REPLACE FUNCTION public.hms_assert_permission(
  _facility_id uuid,
  _module_id text,
  _action text
)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path=''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF lower(_action) NOT IN ('read','write','approve','configure') THEN
    RAISE EXCEPTION 'Unsupported HMS permission action: %',_action;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.hms_module_catalog WHERE module_id=_module_id
  ) THEN
    RAISE EXCEPTION 'Unknown HMS module: %',_module_id;
  END IF;
  IF NOT public.hms_module_is_enabled(_facility_id,_module_id) THEN
    RAISE EXCEPTION 'HMS module % is disabled for this facility',_module_id;
  END IF;
  IF public.has_role(auth.uid(),'admin'::public.app_role) THEN
    RETURN;
  END IF;
  IF NOT private.hms_authorize(auth.uid(),_facility_id,_module_id,_action) THEN
    RAISE EXCEPTION 'Permission denied: % %',_module_id,lower(_action);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.hms_has_permission(uuid,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.hms_assert_permission(uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.hms_has_permission(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_assert_permission(uuid,text,text) TO authenticated;

-- Configuration changes remain administrator-only. The broader permission
-- matrix controls workflow use; it never grants module configuration itself.
CREATE OR REPLACE FUNCTION public.set_hms_role_module_permission(
  _role_code text,
  _module_code text,
  _can_read boolean,
  _can_write boolean,
  _can_approve boolean,
  _can_configure boolean,
  _scope_code text DEFAULT 'facility'
)
RETURNS public.hms_role_module_permissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $$
DECLARE r public.hms_role_module_permissions;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Administrator authorization required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.hms_role_catalog WHERE role_code=_role_code AND active=true) THEN
    RAISE EXCEPTION 'Unknown or inactive HMS role';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.hms_module_catalog WHERE module_code=_module_code) THEN
    RAISE EXCEPTION 'Unknown HMS module code';
  END IF;
  IF _scope_code NOT IN ('none','facility','department','user','global') THEN
    RAISE EXCEPTION 'Invalid permission scope';
  END IF;
  IF _role_code='super_admin' AND (
    NOT _can_read OR NOT _can_write OR NOT _can_approve OR NOT _can_configure OR _scope_code<>'global'
  ) THEN
    RAISE EXCEPTION 'Super Admin permissions are immutable and must remain full/global';
  END IF;
  INSERT INTO public.hms_role_module_permissions(role_code,module_code,can_read,can_write,can_approve,can_configure,scope_code)
  VALUES(_role_code,_module_code,_can_read,_can_write,_can_approve,_can_configure,_scope_code)
  ON CONFLICT(role_code,module_code) DO UPDATE
  SET can_read=EXCLUDED.can_read,can_write=EXCLUDED.can_write,
      can_approve=EXCLUDED.can_approve,can_configure=EXCLUDED.can_configure,
      scope_code=EXCLUDED.scope_code
  RETURNING * INTO r;
  RETURN r;
END;
$$;

REVOKE ALL ON FUNCTION public.set_hms_role_module_permission(text,text,boolean,boolean,boolean,boolean,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_hms_role_module_permission(text,text,boolean,boolean,boolean,boolean,text) TO authenticated;

-- Reapply the governed import functions with the canonical HMS permission boundary.
-- Governed import lifecycle: staging -> validation -> approval -> atomic commit/rollback.
CREATE OR REPLACE FUNCTION public.create_hms_import_batch(_template_code text,_source_filename text,_rows jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_template hms_import_templates%ROWTYPE; v_batch uuid; v_row jsonb; v_no int:=0; v_facility uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT f.id INTO v_facility FROM public.healthcare_facilities f ORDER BY f.created_at LIMIT 1;
 IF v_facility IS NULL THEN RAISE EXCEPTION 'No facility is configured for HMS import'; END IF;
 PERFORM public.hms_assert_permission(v_facility,'data-import','write');
 SELECT * INTO v_template FROM public.hms_import_templates WHERE code=_template_code AND status='active' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active import template not found'; END IF;
 IF jsonb_typeof(_rows) <> 'array' OR jsonb_array_length(_rows)=0 THEN RAISE EXCEPTION 'Import rows must be a non-empty JSON array'; END IF;
 INSERT INTO public.hms_import_batches(template_id,template_version,source_filename,row_count,created_by)
 VALUES(v_template.id,v_template.current_version,_source_filename,jsonb_array_length(_rows),auth.uid()) RETURNING id INTO v_batch;
 FOR v_row IN SELECT value FROM jsonb_array_elements(_rows) LOOP
   v_no:=v_no+1;
   INSERT INTO public.hms_import_staging(batch_id,row_number,payload) VALUES(v_batch,v_no,v_row);
 END LOOP;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id,details) VALUES(v_batch,'created',auth.uid(),jsonb_build_object('rows',jsonb_array_length(_rows)));
 RETURN v_batch;
END $$;
REVOKE ALL ON FUNCTION public.create_hms_import_batch(text,text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_hms_import_batch(text,text,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_hms_import_batch(_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b hms_import_batches%ROWTYPE; s record; err_count int:=0; quarantine_count int:=0; valid_count int:=0; p jsonb; v_facility uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN RAISE EXCEPTION 'Import administrator authorization required'; END IF;
 SELECT * INTO b FROM public.hms_import_batches WHERE id=_batch_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Import batch not found'; END IF;
 IF b.status NOT IN ('uploaded','validating','validated','quarantined') THEN RAISE EXCEPTION 'Batch cannot be validated in status %',b.status; END IF;
 UPDATE public.hms_import_batches SET status='validating' WHERE id=_batch_id;
 DELETE FROM public.hms_import_errors WHERE batch_id=_batch_id;
 UPDATE public.hms_import_staging SET validation_status='pending',validation_errors='[]'::jsonb WHERE batch_id=_batch_id;
 FOR s IN SELECT * FROM public.hms_import_staging WHERE batch_id=_batch_id ORDER BY row_number FOR UPDATE LOOP
   p:=s.payload;
   IF jsonb_typeof(p)<>'object' THEN
     UPDATE public.hms_import_staging SET validation_status='reject',validation_errors='["ROW_NOT_OBJECT"]'::jsonb WHERE id=s.id;
     INSERT INTO public.hms_import_errors(batch_id,staging_id,severity,code,message) VALUES(_batch_id,s.id,'REJECT','ROW_NOT_OBJECT','Each imported row must be an object'); err_count:=err_count+1; CONTINUE;
   END IF;
   IF (SELECT module_code FROM public.hms_import_templates t WHERE t.id=b.template_id)='M1' AND (coalesce(nullif(trim(p->>'first_name'),''),'')='' OR coalesce(nullif(trim(p->>'last_name'),''),'')='') THEN
     UPDATE public.hms_import_staging SET validation_status='quarantine',validation_errors='["PATIENT_NAME_REQUIRED"]'::jsonb WHERE id=s.id;
     INSERT INTO public.hms_import_quarantine(staging_id) VALUES(s.id);
     INSERT INTO public.hms_import_errors(batch_id,staging_id,severity,code,message) VALUES(_batch_id,s.id,'QUARANTINE','PATIENT_NAME_REQUIRED','Patient first_name and last_name are required'); quarantine_count:=quarantine_count+1; CONTINUE;
   END IF;
   UPDATE public.hms_import_staging SET validation_status='pass',normalized_payload=p WHERE id=s.id; valid_count:=valid_count+1;
 END LOOP;
 UPDATE public.hms_import_batches SET status=CASE WHEN err_count>0 AND valid_count=0 THEN 'quarantined' WHEN err_count>0 OR quarantine_count>0 THEN 'quarantined' ELSE 'validated' END,accepted_count=valid_count,rejected_count=err_count,quarantine_count=quarantine_count WHERE id=_batch_id;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id,details) VALUES(_batch_id,'validated',auth.uid(),jsonb_build_object('valid',valid_count,'rejected',err_count,'quarantine',quarantine_count));
 RETURN jsonb_build_object('batch_id',_batch_id,'valid',valid_count,'rejected',err_count,'quarantine',quarantine_count);
END $$;
REVOKE ALL ON FUNCTION public.validate_hms_import_batch(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.validate_hms_import_batch(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.approve_hms_import_batch(_batch_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b hms_import_batches%ROWTYPE; v_facility uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT f.id INTO v_facility FROM public.healthcare_facilities f ORDER BY f.created_at LIMIT 1;
 IF v_facility IS NULL THEN RAISE EXCEPTION 'No facility is configured for HMS import'; END IF;
 PERFORM public.hms_assert_permission(v_facility,'data-import','approve');
 SELECT * INTO b FROM public.hms_import_batches WHERE id=_batch_id FOR UPDATE;
 IF NOT FOUND OR b.status<>'validated' THEN RAISE EXCEPTION 'Only a fully validated batch may be approved'; END IF;
 UPDATE public.hms_import_batches SET status='approved',approved_by=auth.uid() WHERE id=_batch_id;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id) VALUES(_batch_id,'approved',auth.uid());
END $$;
REVOKE ALL ON FUNCTION public.approve_hms_import_batch(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.approve_hms_import_batch(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.commit_hms_import_batch(_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b hms_import_batches%ROWTYPE; t hms_import_templates%ROWTYPE; s record; inserted int:=0; allowed jsonb; v_facility uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT f.id INTO v_facility FROM public.healthcare_facilities f ORDER BY f.created_at LIMIT 1;
 IF v_facility IS NULL THEN RAISE EXCEPTION 'No facility is configured for HMS import'; END IF;
 PERFORM public.hms_assert_permission(v_facility,'data-import','approve');
 SELECT * INTO b FROM public.hms_import_batches WHERE id=_batch_id FOR UPDATE;
 IF NOT FOUND OR b.status<>'approved' THEN RAISE EXCEPTION 'Only approved batches may be committed'; END IF;
 SELECT * INTO t FROM public.hms_import_templates WHERE id=b.template_id;
 IF t.module_code<>'M1' OR t.entity_name<>'patients' THEN RAISE EXCEPTION 'No governed commit adapter exists for template %',t.code; END IF;
 IF EXISTS(SELECT 1 FROM public.hms_import_staging WHERE batch_id=_batch_id AND validation_status<>'pass') THEN RAISE EXCEPTION 'Batch contains non-pass rows'; END IF;
 FOR s IN SELECT normalized_payload FROM public.hms_import_staging WHERE batch_id=_batch_id ORDER BY row_number LOOP
   allowed:=jsonb_build_object(
     'first_name',s.normalized_payload->'first_name','last_name',s.normalized_payload->'last_name',
     'date_of_birth',s.normalized_payload->'date_of_birth','gender',s.normalized_payload->'gender',
     'phone',s.normalized_payload->'phone','email',s.normalized_payload->'email',
     'address',s.normalized_payload->'address','city',s.normalized_payload->'city',
     'ghana_card_number',s.normalized_payload->'ghana_card_number','blood_group',s.normalized_payload->'blood_group',
     'genotype',s.normalized_payload->'genotype','allergies',s.normalized_payload->'allergies',
     'chronic_conditions',s.normalized_payload->'chronic_conditions',
     'insurance_provider',s.normalized_payload->'insurance_provider','insurance_number',s.normalized_payload->'insurance_number',
     'emergency_contact_name',s.normalized_payload->'emergency_contact_name','emergency_contact_phone',s.normalized_payload->'emergency_contact_phone');
   INSERT INTO public.patients SELECT (jsonb_populate_record(NULL::public.patients,allowed)).*;
   inserted:=inserted+1;
 END LOOP;
 UPDATE public.hms_import_batches SET status='committed',committed_by=auth.uid(),committed_at=now(),accepted_count=inserted WHERE id=_batch_id;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id,details) VALUES(_batch_id,'committed',auth.uid(),jsonb_build_object('inserted',inserted));
 RETURN jsonb_build_object('batch_id',_batch_id,'status','committed','inserted',inserted);
EXCEPTION WHEN OTHERS THEN
 UPDATE public.hms_import_batches SET status='commit_failed' WHERE id=_batch_id;
 INSERT INTO public.hms_import_audit(batch_id,action,actor_id,details) VALUES(_batch_id,'commit_failed',auth.uid(),jsonb_build_object('error',SQLERRM));
 RAISE;
END $$;
REVOKE ALL ON FUNCTION public.commit_hms_import_batch(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.commit_hms_import_batch(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rollback_hms_import_batch(_batch_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE b hms_import_batches%ROWTYPE; v_facility uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT f.id INTO v_facility FROM public.healthcare_facilities f ORDER BY f.created_at LIMIT 1;
 IF v_facility IS NULL THEN RAISE EXCEPTION 'No facility is configured for HMS import'; END IF;
 PERFORM public.hms_assert_permission(v_facility,'data-import','approve');
 SELECT * INTO b FROM public.hms_import_batches WHERE id=_batch_id FOR UPDATE;
 IF NOT FOUND OR b.status<>'committed' OR b.committed_at < now()-interval '30 days' THEN RAISE EXCEPTION 'Batch is not eligible for rollback'; END IF;
 RAISE EXCEPTION 'Rollback requires an entity-specific compensating adapter; direct deletion is prohibited';
END $$;
REVOKE ALL ON FUNCTION public.rollback_hms_import_batch(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.rollback_hms_import_batch(uuid) TO authenticated;

REVOKE ALL ON TABLE public.hms_import_templates,public.hms_import_template_versions,public.hms_import_batches,public.hms_import_staging,public.hms_import_errors,public.hms_import_quarantine,public.hms_import_mappings,public.hms_import_audit FROM authenticated;
GRANT SELECT ON public.hms_import_templates,public.hms_import_template_versions,public.hms_import_batches,public.hms_import_staging,public.hms_import_errors,public.hms_import_quarantine,public.hms_import_mappings,public.hms_import_audit TO authenticated;
