-- Next-gen enterprise expansion and facility service-availability governance.
-- A module is usable only when the facility explicitly provides the service.
-- Existing canonical modules remain enabled by their existing defaults; new services
-- are opt-in and cannot be enabled until service availability is declared.

ALTER TABLE public.hms_facility_modules
  ADD COLUMN IF NOT EXISTS service_available boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS readiness_status text NOT NULL DEFAULT 'not_available'
    CHECK (readiness_status IN ('not_available','planned','ready','suspended')),
  ADD COLUMN IF NOT EXISTS service_notes text,
  ADD COLUMN IF NOT EXISTS verified_by uuid,
  ADD COLUMN IF NOT EXISTS verified_at timestamptz;

-- Existing non-optional catalogue entries are treated as available unless a facility
-- explicitly records otherwise. New optional modules remain unavailable until enabled.
UPDATE public.hms_module_catalog
SET default_enabled = CASE WHEN optional THEN false ELSE true END
WHERE module_id IN (
  'physiotherapy','dietary-restaurant','teaching-research','asset-biomedical',
  'procurement','data-import','report-centre','user-role-management'
);

INSERT INTO public.hms_module_catalog
(module_id,module_code,module_name,category,optional,safety_level,default_enabled,description)
VALUES
('hr-payroll','M26','HR & Payroll','enterprise',true,'high',false,'Employee records, leave, attendance, payroll and statutory deductions'),
('icu-critical-care','M27','ICU & Critical Care','clinical',true,'critical',false,'Critical-care stays, observations, escalation and device-linked care'),
('mental-health','M28','Mental Health','clinical',true,'high',false,'Mental-health assessment, care planning and follow-up'),
('social-work','M29','Social Work','care-coordination',true,'high',false,'Psychosocial assessment, safeguarding and social-care coordination'),
('quality-compliance','M30','Quality & Compliance','governance',true,'high',false,'Quality incidents, CAPA, compliance evidence and review'),
('infection-control','M31','Infection Prevention & Control','governance',true,'high',false,'IPC surveillance, exposure events and corrective actions'),
('mortuary','M32','Mortuary','support',true,'high',false,'Mortuary case intake, custody, release and traceability'),
('ambulance','M33','Ambulance & Transport','emergency',true,'high',false,'Ambulance fleet, dispatch, crew, trip and handover lifecycle'),
('research-portal','M34','Research Portal','education',true,'high',false,'Research projects, governed datasets, ethics and retention'),
('external-audit','M35','External Audit','governance',true,'high',false,'Controlled auditor access, evidence requests and audit trails'),
('genomics','M36','Genomics','diagnostics',true,'critical',false,'Genomic orders, specimens, findings, consent and provenance')
ON CONFLICT(module_id) DO UPDATE
SET module_code=excluded.module_code,module_name=excluded.module_name,category=excluded.category,
    optional=excluded.optional,safety_level=excluded.safety_level,description=excluded.description,
    updated_at=now();

-- Target tertiary-hospital specialist identities. These are specialized HMS roles,
-- not replacement application roles; existing app_role remains the authentication
-- compatibility layer.
INSERT INTO public.hms_role_catalog(role_code,role_name,group_code,external_role,advisory_only)
VALUES
('hospital_director','Hospital Director','governance',false,false),
('consultant','Consultant / Specialist Doctor','clinical',false,false),
('resident','Resident / House Officer','clinical',false,false),
('triage_nurse','Triage Nurse','clinical',false,false),
('pathologist','Pathologist','clinical',false,false),
('blood_bank_officer','Blood Bank Officer','clinical',false,false),
('anesthesiologist','Anesthesiologist','clinical',false,false),
('icu_intensivist','ICU Intensivist','clinical',false,false),
('emergency_physician','Emergency Physician','clinical',false,false),
('occupational_therapist','Occupational Therapist','clinical',false,false),
('psychologist','Psychologist / Psychiatrist','clinical',false,false),
('social_worker','Social Worker','support',false,false),
('hr_officer','HR Officer','support',false,false),
('payroll_officer','Payroll Officer','support',false,false),
('supply_chain_officer','Supply Chain Officer','support',false,false),
('compliance_officer','Compliance / Legal Officer','governance',false,false),
('qa_officer','Quality Assurance Officer','governance',false,false),
('infection_control_officer','Infection Control Officer','governance',false,false),
('public_health_officer','Public Health Officer','reporting',false,false),
('mortuary_attendant','Mortuary Attendant','support',false,false),
('paramedic','Paramedic / Ambulance Officer','emergency',false,false),
('external_auditor','External Auditor','external',true,false)
ON CONFLICT(role_code) DO UPDATE SET role_name=excluded.role_name,group_code=excluded.group_code,external_role=excluded.external_role,updated_at=now();

-- Facility-scoped specialization assignments allow one application identity
-- (e.g. practitioner) to hold several governed tertiary roles without duplicating
-- the authentication/RBAC model.
CREATE TABLE IF NOT EXISTS public.hms_user_role_assignments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL,
 role_code text NOT NULL REFERENCES public.hms_role_catalog(role_code) ON DELETE RESTRICT,
 facility_id uuid NOT NULL,
 department_code text,
 active boolean NOT NULL DEFAULT true,
 effective_from timestamptz NOT NULL DEFAULT now(),
 effective_to timestamptz,
 assigned_by uuid,
 assigned_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(user_id,role_code,facility_id)
);
ALTER TABLE public.hms_user_role_assignments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS hms_user_role_assignments_admin ON public.hms_user_role_assignments;
CREATE POLICY hms_user_role_assignments_admin ON public.hms_user_role_assignments
 FOR ALL TO authenticated
 USING(public.has_role((SELECT auth.uid()),'admin'::public.app_role))
 WITH CHECK(public.has_role((SELECT auth.uid()),'admin'::public.app_role));

-- Enterprise operational records. These are deliberately additive and use the
-- existing patient/facility/user identities rather than creating parallel identities.
CREATE TABLE IF NOT EXISTS public.hms_hr_employees (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, user_id uuid,
 employee_number text NOT NULL, full_name text NOT NULL, department_code text,
 job_title text, employment_status text NOT NULL DEFAULT 'active',
 hire_date date, termination_date date, credentials jsonb NOT NULL DEFAULT '{}',
 created_by uuid, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(facility_id,employee_number)
);
CREATE TABLE IF NOT EXISTS public.hms_hr_leave_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), employee_id uuid NOT NULL REFERENCES public.hms_hr_employees(id) ON DELETE CASCADE,
 leave_type text NOT NULL, start_date date NOT NULL, end_date date NOT NULL, status text NOT NULL DEFAULT 'pending',
 reason text, approved_by uuid, approved_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(end_date>=start_date)
);
CREATE TABLE IF NOT EXISTS public.hms_payroll_periods (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, period_start date NOT NULL, period_end date NOT NULL,
 status text NOT NULL DEFAULT 'draft', approved_by uuid, approved_at timestamptz, created_by uuid, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(facility_id,period_start,period_end)
);
CREATE TABLE IF NOT EXISTS public.hms_payroll_items (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), payroll_period_id uuid NOT NULL REFERENCES public.hms_payroll_periods(id) ON DELETE CASCADE,
 employee_id uuid NOT NULL REFERENCES public.hms_hr_employees(id), gross_amount numeric(14,2) NOT NULL DEFAULT 0,
 deductions numeric(14,2) NOT NULL DEFAULT 0, net_amount numeric(14,2) GENERATED ALWAYS AS (gross_amount-deductions) STORED,
 details jsonb NOT NULL DEFAULT '{}', UNIQUE(payroll_period_id,employee_id), CHECK(gross_amount>=0 AND deductions>=0 AND deductions<=gross_amount)
);

CREATE TABLE IF NOT EXISTS public.hms_icu_stays (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, patient_id uuid NOT NULL, encounter_id uuid,
 bed_reference text, admission_at timestamptz NOT NULL DEFAULT now(), discharge_at timestamptz,
 acuity text NOT NULL DEFAULT 'high', status text NOT NULL DEFAULT 'active', diagnosis jsonb NOT NULL DEFAULT '{}',
 created_by uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.hms_icu_observations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), stay_id uuid NOT NULL REFERENCES public.hms_icu_stays(id) ON DELETE CASCADE,
 observed_at timestamptz NOT NULL DEFAULT now(), observed_by uuid NOT NULL, observations jsonb NOT NULL DEFAULT '{}',
 escalation_level text NOT NULL DEFAULT 'routine', created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.hms_mental_health_assessments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, patient_id uuid NOT NULL, encounter_id uuid,
 assessor_id uuid NOT NULL, assessment jsonb NOT NULL DEFAULT '{}', risk_level text NOT NULL DEFAULT 'unknown',
 care_plan jsonb NOT NULL DEFAULT '{}', status text NOT NULL DEFAULT 'draft', created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.hms_social_work_cases (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, patient_id uuid NOT NULL, encounter_id uuid,
 assigned_to uuid, case_type text NOT NULL, assessment jsonb NOT NULL DEFAULT '{}', interventions jsonb NOT NULL DEFAULT '{}',
 safeguarding_level text NOT NULL DEFAULT 'none', status text NOT NULL DEFAULT 'open', created_at timestamptz NOT NULL DEFAULT now(),
 closed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.hms_quality_incidents (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, incident_code text NOT NULL, category text NOT NULL,
 severity text NOT NULL DEFAULT 'moderate', patient_id uuid, description text NOT NULL, status text NOT NULL DEFAULT 'open',
 reported_by uuid NOT NULL, owner_id uuid, occurred_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(facility_id,incident_code)
);
CREATE TABLE IF NOT EXISTS public.hms_quality_actions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), incident_id uuid NOT NULL REFERENCES public.hms_quality_incidents(id) ON DELETE CASCADE,
 action_type text NOT NULL, description text NOT NULL, owner_id uuid, due_date date, status text NOT NULL DEFAULT 'open',
 completed_at timestamptz, evidence jsonb NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS public.hms_ipc_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, patient_id uuid, event_type text NOT NULL,
 organism text, location text, risk_level text NOT NULL DEFAULT 'moderate', status text NOT NULL DEFAULT 'open',
 reported_by uuid NOT NULL, event_at timestamptz, actions jsonb NOT NULL DEFAULT '{}', created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.hms_mortuary_cases (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, patient_id uuid, case_number text NOT NULL,
 received_at timestamptz NOT NULL DEFAULT now(), storage_location text, custody_status text NOT NULL DEFAULT 'received',
 release_to text, released_at timestamptz, released_by uuid, identity_verification jsonb NOT NULL DEFAULT '{}',
 created_by uuid, UNIQUE(facility_id,case_number)
);
CREATE TABLE IF NOT EXISTS public.hms_ambulance_trips (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, patient_id uuid, ambulance_reference text,
 dispatched_at timestamptz, departed_at timestamptz, arrived_at timestamptz, returned_at timestamptz,
 pickup_location text, destination text, crew jsonb NOT NULL DEFAULT '[]', status text NOT NULL DEFAULT 'requested',
 clinical_handover jsonb NOT NULL DEFAULT '{}', requested_by uuid, created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.hms_research_projects (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, project_code text NOT NULL, title text NOT NULL,
 protocol_version text, ethics_reference text, status text NOT NULL DEFAULT 'draft', principal_investigator uuid,
 data_purpose text NOT NULL, de_identified boolean NOT NULL DEFAULT true, retention_until date,
 created_by uuid, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(facility_id,project_code)
);
CREATE TABLE IF NOT EXISTS public.hms_research_data_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), project_id uuid NOT NULL REFERENCES public.hms_research_projects(id) ON DELETE CASCADE,
 requested_by uuid NOT NULL, data_scope jsonb NOT NULL, approval_status text NOT NULL DEFAULT 'pending',
 approved_by uuid, approved_at timestamptz, de_identification_method text, expires_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.hms_audit_engagements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, auditor_user_id uuid, audit_type text NOT NULL,
 scope jsonb NOT NULL DEFAULT '{}', status text NOT NULL DEFAULT 'planned', starts_on date, ends_on date,
 evidence_request jsonb NOT NULL DEFAULT '{}', created_by uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.hms_genomics_orders (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), facility_id uuid NOT NULL, patient_id uuid NOT NULL, encounter_id uuid,
 ordered_by uuid NOT NULL, test_code text NOT NULL, specimen_reference text, consent_reference text,
 status text NOT NULL DEFAULT 'ordered', result_summary jsonb NOT NULL DEFAULT '{}', provenance jsonb NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT now()
);

DO $$ DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY[
  'hms_user_role_assignments','hms_hr_employees','hms_hr_leave_requests','hms_payroll_periods','hms_payroll_items',
  'hms_icu_stays','hms_icu_observations','hms_mental_health_assessments','hms_social_work_cases',
  'hms_quality_incidents','hms_quality_actions','hms_ipc_events','hms_mortuary_cases','hms_ambulance_trips',
  'hms_research_projects','hms_research_data_requests','hms_audit_engagements','hms_genomics_orders'
 ] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',t||'_admin',t);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING(public.has_role((SELECT auth.uid()),''admin''::public.app_role)) WITH CHECK(public.has_role((SELECT auth.uid()),''admin''::public.app_role))',t||'_admin',t);
  EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',t||'_service',t);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO service_role USING(true) WITH CHECK(true)',t||'_service',t);
 END LOOP;
END $$;

-- Facility service readiness is the prerequisite for activation.
CREATE OR REPLACE FUNCTION public.set_hms_facility_module_service(
 _facility_id uuid,_module_id text,_service_available boolean,_readiness_status text DEFAULT NULL,_service_notes text DEFAULT NULL
)
RETURNS public.hms_facility_modules
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r public.hms_facility_modules; v_status text;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN RAISE EXCEPTION 'Administrator authorization required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.hms_module_catalog WHERE module_id=_module_id) THEN RAISE EXCEPTION 'Unknown HMS module'; END IF;
 v_status:=COALESCE(_readiness_status,CASE WHEN _service_available THEN 'ready' ELSE 'not_available' END);
 IF _service_available AND v_status<>'ready' THEN RAISE EXCEPTION 'Available services must have readiness_status=ready'; END IF;
 INSERT INTO public.hms_facility_modules(facility_id,module_id,enabled,service_available,readiness_status,service_notes,verified_by,verified_at,configured_by)
 VALUES(_facility_id,_module_id,_service_available,_service_available,v_status,_service_notes,auth.uid(),CASE WHEN _service_available THEN now() END,auth.uid())
 ON CONFLICT(facility_id,module_id) DO UPDATE SET
   service_available=excluded.service_available,
   readiness_status=excluded.readiness_status,
   service_notes=excluded.service_notes,
   verified_by=auth.uid(),
   verified_at=CASE WHEN excluded.service_available THEN now() ELSE NULL END,
   enabled=CASE WHEN excluded.service_available THEN hms_facility_modules.enabled ELSE false END,
   configured_by=auth.uid(),configured_at=now(),effective_from=now(),effective_to=NULL
 RETURNING * INTO r;
 RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.set_hms_facility_module_service(uuid,text,boolean,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_hms_facility_module_service(uuid,text,boolean,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_hms_facility_module(_facility_id uuid,_module_id text,_enabled boolean)
RETURNS public.hms_facility_modules
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r public.hms_facility_modules; v_available boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'admin'::public.app_role) THEN RAISE EXCEPTION 'Administrator authorization required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.hms_module_catalog WHERE module_id=_module_id) THEN RAISE EXCEPTION 'Unknown HMS module'; END IF;
 SELECT COALESCE(service_available,false) INTO v_available FROM public.hms_facility_modules WHERE facility_id=_facility_id AND module_id=_module_id;
 IF _enabled AND NOT COALESCE(v_available,(SELECT NOT optional FROM public.hms_module_catalog WHERE module_id=_module_id)) THEN
   RAISE EXCEPTION 'Cannot enable HMS module % until the facility declares the service available',_module_id;
 END IF;
 INSERT INTO public.hms_facility_modules(facility_id,module_id,enabled,service_available,readiness_status,configured_by)
 VALUES(_facility_id,_module_id,_enabled,COALESCE(v_available,_enabled),CASE WHEN COALESCE(v_available,_enabled) THEN 'ready' ELSE 'not_available' END,auth.uid())
 ON CONFLICT(facility_id,module_id) DO UPDATE SET enabled=excluded.enabled,configured_by=auth.uid(),configured_at=now(),effective_from=now(),effective_to=NULL
 RETURNING * INTO r; RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.set_hms_facility_module(uuid,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_hms_facility_module(uuid,text,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.hms_module_is_enabled(_facility_id uuid,_module_id text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT EXISTS(
   SELECT 1 FROM public.hms_facility_modules fm
   WHERE fm.facility_id=_facility_id AND fm.module_id=_module_id
     AND fm.enabled=true AND fm.service_available=true
     AND fm.effective_from<=now() AND (fm.effective_to IS NULL OR fm.effective_to>now())
 ) OR (
   EXISTS(SELECT 1 FROM public.hms_module_catalog mc WHERE mc.module_id=_module_id AND mc.default_enabled=true)
   AND NOT EXISTS(SELECT 1 FROM public.hms_facility_modules fm WHERE fm.facility_id=_facility_id AND fm.module_id=_module_id)
 );
$$;
REVOKE ALL ON FUNCTION public.hms_module_is_enabled(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.hms_module_is_enabled(uuid,text) TO authenticated;

-- Specialized role assignments participate in canonical authorization while
-- retaining the existing app-role compatibility bridge.
CREATE OR REPLACE FUNCTION private.hms_authorize(
 _user_id uuid,_facility_id uuid,_module_id text,_action text
)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT _user_id IS NOT NULL AND _facility_id IS NOT NULL
 AND public.has_facility_access(_user_id,_facility_id)
 AND public.hms_module_is_enabled(_facility_id,_module_id)
 AND (
   EXISTS (
    SELECT 1 FROM public.user_roles ur
    JOIN public.hms_app_role_map arm ON arm.app_role=ur.role::text AND arm.active=true
    JOIN public.hms_role_module_permissions p ON p.role_code=arm.role_code
    JOIN public.hms_module_catalog mc ON mc.module_code=p.module_code
    WHERE ur.user_id=_user_id AND mc.module_id=_module_id AND p.scope_code IN ('facility','global')
      AND ((lower(_action)='read' AND p.can_read) OR (lower(_action)='write' AND p.can_write) OR
           (lower(_action)='approve' AND p.can_approve) OR (lower(_action)='configure' AND p.can_configure))
   )
   OR EXISTS (
    SELECT 1 FROM public.hms_user_role_assignments ura
    JOIN public.hms_role_module_permissions p ON p.role_code=ura.role_code
    JOIN public.hms_module_catalog mc ON mc.module_code=p.module_code
    WHERE ura.user_id=_user_id AND ura.facility_id=_facility_id AND ura.active=true
      AND mc.module_id=_module_id AND p.scope_code IN ('facility','global')
      AND ((lower(_action)='read' AND p.can_read) OR (lower(_action)='write' AND p.can_write) OR
           (lower(_action)='approve' AND p.can_approve) OR (lower(_action)='configure' AND p.can_configure))
   )
 );
$$;
REVOKE ALL ON FUNCTION private.hms_authorize(uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.hms_authorize(uuid,uuid,text,text) TO authenticated;

-- Conservative least-privilege permissions for newly introduced services.
WITH grants(role_code,module_code,can_read,can_write,can_approve,can_configure,scope_code) AS (
 VALUES
 ('hospital_director','M30',true,true,true,true,'facility'),
 ('hr_officer','M26',true,true,true,false,'facility'),
 ('payroll_officer','M26',true,true,true,false,'facility'),
 ('supply_chain_officer','M23-P',true,true,true,false,'facility'),
 ('icu_intensivist','M27',true,true,true,false,'facility'),
 ('emergency_physician','M33',true,true,true,false,'facility'),
 ('psychologist','M28',true,true,false,false,'facility'),
 ('social_worker','M29',true,true,false,false,'facility'),
 ('qa_officer','M30',true,true,true,false,'facility'),
 ('infection_control_officer','M31',true,true,true,false,'facility'),
 ('mortuary_attendant','M32',true,true,true,false,'facility'),
 ('paramedic','M33',true,true,false,false,'facility'),
 ('researcher','M34',true,true,false,false,'facility'),
 ('external_auditor','M35',true,false,false,false,'facility'),
 ('pathologist','M1',true,true,true,false,'facility'),
 ('blood_bank_officer','M5',true,true,true,false,'facility'),
 ('anesthesiologist','M8',true,true,true,false,'facility'),
 ('occupational_therapist','M7',true,true,false,false,'facility'),
 ('consultant','M3',true,true,true,false,'facility'),
 ('surgeon','M8',true,true,true,false,'facility')
)
INSERT INTO public.hms_role_module_permissions(role_code,module_code,can_read,can_write,can_approve,can_configure,scope_code)
SELECT * FROM grants
ON CONFLICT(role_code,module_code) DO UPDATE SET can_read=excluded.can_read,can_write=excluded.can_write,
 can_approve=excluded.can_approve,can_configure=excluded.can_configure,scope_code=excluded.scope_code;

COMMENT ON TABLE public.hms_facility_modules IS 'Facility service catalogue. A module may be enabled only when service_available=true; optional services are off by default.';
COMMENT ON COLUMN public.hms_facility_modules.service_available IS 'Whether this facility actually provides the service represented by the module.';
COMMENT ON COLUMN public.hms_facility_modules.readiness_status IS 'Operational readiness: not_available, planned, ready or suspended.';
