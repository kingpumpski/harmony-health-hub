-- Enterprise HIMS expansion: inpatient capacity, nursing continuity, emergency, theatre,
-- transfusion safety and insurance lifecycle. Additive only; no legacy tables are replaced.

CREATE TABLE IF NOT EXISTS public.wards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  code TEXT NOT NULL UNIQUE,
  department TEXT,
  floor TEXT,
  gender_policy TEXT NOT NULL DEFAULT 'mixed' CHECK (gender_policy IN ('mixed','male','female','paediatric')),
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.beds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ward_id UUID NOT NULL REFERENCES public.wards(id) ON DELETE CASCADE,
  bed_number TEXT NOT NULL,
  bed_type TEXT NOT NULL DEFAULT 'standard',
  status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available','occupied','reserved','maintenance','blocked')),
  patient_id UUID,
  admission_id UUID,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (ward_id, bed_number)
);

CREATE TABLE IF NOT EXISTS public.nursing_care_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  admission_id UUID,
  problem TEXT NOT NULL,
  goal TEXT NOT NULL,
  interventions TEXT,
  evaluation TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','on_hold','completed','cancelled')),
  priority TEXT NOT NULL DEFAULT 'routine' CHECK (priority IN ('routine','high','critical')),
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.nursing_shift_handovers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  admission_id UUID,
  outgoing_officer UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  incoming_officer UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  shift_date DATE NOT NULL DEFAULT CURRENT_DATE,
  shift_name TEXT NOT NULL DEFAULT 'general',
  clinical_summary TEXT NOT NULL,
  outstanding_tasks TEXT,
  risks_and_alerts TEXT,
  escalation_required BOOLEAN NOT NULL DEFAULT false,
  acknowledged_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.emergency_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID,
  arrival_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  arrival_mode TEXT NOT NULL DEFAULT 'walk_in' CHECK (arrival_mode IN ('walk_in','ambulance','referral','police','other')),
  triage_priority TEXT NOT NULL DEFAULT 'urgent' CHECK (triage_priority IN ('critical','urgent','moderate','routine')),
  chief_complaint TEXT,
  assigned_officer UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting','triage','treatment','observation','admitted','transferred','discharged','deceased')),
  disposition TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.theatre_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  procedure_name TEXT NOT NULL,
  theatre TEXT,
  surgeon_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  anaesthetist_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  scheduled_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','cleared','in_progress','completed','cancelled','postponed')),
  anaesthetic_cleared BOOLEAN NOT NULL DEFAULT false,
  consent_confirmed BOOLEAN NOT NULL DEFAULT false,
  notes TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.transfusion_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  blood_group TEXT,
  component TEXT NOT NULL CHECK (component IN ('whole_blood','red_cells','platelets','plasma','cryoprecipitate','other')),
  unit_identifier TEXT,
  compatibility_checked BOOLEAN NOT NULL DEFAULT false,
  consent_confirmed BOOLEAN NOT NULL DEFAULT false,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','verified','running','completed','stopped','reaction')),
  reaction_notes TEXT,
  administered_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  witnessed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.insurance_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL,
  payer_name TEXT NOT NULL,
  policy_number TEXT,
  eligibility_status TEXT NOT NULL DEFAULT 'unknown' CHECK (eligibility_status IN ('unknown','eligible','ineligible','pending','expired')),
  eligibility_checked_at TIMESTAMPTZ,
  authorization_number TEXT,
  claim_status TEXT NOT NULL DEFAULT 'not_submitted' CHECK (claim_status IN ('not_submitted','draft','submitted','under_review','approved','partially_approved','rejected','paid','appealed')),
  claim_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (claim_amount >= 0),
  approved_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (approved_amount >= 0),
  rejection_reason TEXT,
  checked_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_beds_ward_status ON public.beds(ward_id, status);
CREATE INDEX IF NOT EXISTS idx_beds_patient ON public.beds(patient_id);
CREATE INDEX IF NOT EXISTS idx_careplans_patient_status ON public.nursing_care_plans(patient_id, status);
CREATE INDEX IF NOT EXISTS idx_handover_patient_date ON public.nursing_shift_handovers(patient_id, shift_date DESC);
CREATE INDEX IF NOT EXISTS idx_emergency_status_priority ON public.emergency_cases(status, triage_priority, arrival_at);
CREATE INDEX IF NOT EXISTS idx_theatre_schedule_status ON public.theatre_cases(scheduled_at, status);
CREATE INDEX IF NOT EXISTS idx_transfusion_patient_status ON public.transfusion_records(patient_id, status);
CREATE INDEX IF NOT EXISTS idx_insurance_patient_status ON public.insurance_cases(patient_id, claim_status);

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['wards','beds','nursing_care_plans','emergency_cases','theatre_cases','transfusion_records','insurance_cases'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS t_%s_updated_at ON public.%I', t, t);
    EXECUTE format('CREATE TRIGGER t_%s_updated_at BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at()', t, t);
  END LOOP;
END $$;

ALTER TABLE public.wards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.beds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nursing_care_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nursing_shift_handovers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.theatre_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transfusion_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurance_cases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "clinical operations read" ON public.wards;
CREATE POLICY "clinical operations read" ON public.wards FOR SELECT TO authenticated USING (public.has_role(auth.uid(), ARRAY['admin','practitioner','nurse','midwife','specialist_nurse','front_desk']::public.app_role[]));
DROP POLICY IF EXISTS "clinical operations read beds" ON public.beds;
CREATE POLICY "clinical operations read beds" ON public.beds FOR SELECT TO authenticated USING (public.has_role(auth.uid(), ARRAY['admin','practitioner','nurse','midwife','specialist_nurse','front_desk']::public.app_role[]));
DROP POLICY IF EXISTS "clinical operations manage" ON public.beds;
CREATE POLICY "clinical operations manage" ON public.beds FOR ALL TO authenticated USING (public.has_role(auth.uid(), ARRAY['admin','nurse','specialist_nurse']::public.app_role[])) WITH CHECK (public.has_role(auth.uid(), ARRAY['admin','nurse','specialist_nurse']::public.app_role[]));

DROP POLICY IF EXISTS "nursing care plans clinical" ON public.nursing_care_plans;
CREATE POLICY "nursing care plans clinical" ON public.nursing_care_plans FOR ALL TO authenticated USING (public.has_role(auth.uid(), ARRAY['admin','practitioner','nurse','midwife','specialist_nurse']::public.app_role[])) WITH CHECK (public.has_role(auth.uid(), ARRAY['admin','practitioner','nurse','midwife','specialist_nurse']::public.app_role[]));
DROP POLICY IF EXISTS "handover clinical" ON public.nursing_shift_handovers;
CREATE POLICY "handover clinical" ON public.nursing_shift_handovers FOR ALL TO authenticated USING (public.has_role(auth.uid(), ARRAY['admin','nurse','midwife','specialist_nurse']::public.app_role[])) WITH CHECK (public.has_role(auth.uid(), ARRAY['admin','nurse','midwife','specialist_nurse']::public.app_role[]));
DROP POLICY IF EXISTS "emergency clinical" ON public.emergency_cases;
CREATE POLICY "emergency clinical" ON public.emergency_cases FOR ALL TO authenticated USING (public.has_role(auth.uid(), ARRAY['admin','practitioner','nurse','midwife','specialist_nurse','front_desk']::public.app_role[])) WITH CHECK (public.has_role(auth.uid(), ARRAY['admin','practitioner','nurse','midwife','specialist_nurse','front_desk']::public.app_role[]));
DROP POLICY IF EXISTS "theatre clinical" ON public.theatre_cases;
CREATE POLICY "theatre clinical" ON public.theatre_cases FOR ALL TO authenticated USING (public.has_role(auth.uid(), ARRAY['admin','practitioner','nurse','specialist_nurse']::public.app_role[])) WITH CHECK (public.has_role(auth.uid(), ARRAY['admin','practitioner','nurse','specialist_nurse']::public.app_role[]));
DROP POLICY IF EXISTS "transfusion clinical" ON public.transfusion_records;
CREATE POLICY "transfusion clinical" ON public.transfusion_records FOR ALL TO authenticated USING (public.has_role(auth.uid(), ARRAY['admin','practitioner','nurse','specialist_nurse']::public.app_role[])) WITH CHECK (public.has_role(auth.uid(), ARRAY['admin','practitioner','nurse','specialist_nurse']::public.app_role[]));
DROP POLICY IF EXISTS "insurance clinical accounts" ON public.insurance_cases;
CREATE POLICY "insurance clinical accounts" ON public.insurance_cases FOR ALL TO authenticated USING (public.has_role(auth.uid(), ARRAY['admin','practitioner','front_desk','accountant']::public.app_role[])) WITH CHECK (public.has_role(auth.uid(), ARRAY['admin','practitioner','front_desk','accountant']::public.app_role[]));

CREATE OR REPLACE FUNCTION public.update_insurance_case(_id UUID, _eligibility TEXT, _authorization TEXT, _claim_status TEXT, _claim_amount NUMERIC, _approved_amount NUMERIC, _rejection_reason TEXT)
RETURNS public.insurance_cases LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), ARRAY['admin','accountant','front_desk']::public.app_role[]) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF _eligibility NOT IN ('unknown','eligible','ineligible','pending','expired') THEN RAISE EXCEPTION 'Invalid eligibility status'; END IF;
  IF _claim_status NOT IN ('not_submitted','draft','submitted','under_review','approved','partially_approved','rejected','paid','appealed') THEN RAISE EXCEPTION 'Invalid claim status'; END IF;
  UPDATE public.insurance_cases SET eligibility_status=_eligibility, eligibility_checked_at=CASE WHEN _eligibility <> 'unknown' THEN now() ELSE eligibility_checked_at END, authorization_number=_authorization, claim_status=_claim_status, claim_amount=GREATEST(COALESCE(_claim_amount,0),0), approved_amount=GREATEST(COALESCE(_approved_amount,0),0), rejection_reason=_rejection_reason, checked_by=auth.uid(), updated_at=now() WHERE id=_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Insurance case not found'; END IF;
  RETURN (SELECT i FROM public.insurance_cases i WHERE i.id=_id);
END; $$;
GRANT EXECUTE ON FUNCTION public.update_insurance_case(UUID,TEXT,TEXT,TEXT,NUMERIC,NUMERIC,TEXT) TO authenticated;
