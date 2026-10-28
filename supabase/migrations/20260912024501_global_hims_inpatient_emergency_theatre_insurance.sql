-- Global HIMS expansion: inpatient capacity, emergency, theatre, transfusion and insurance lifecycle.
-- Additive by design: does not replace legacy tables.

CREATE TABLE IF NOT EXISTS public.ward_units (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  code TEXT NOT NULL UNIQUE,
  specialty TEXT,
  gender_policy TEXT NOT NULL DEFAULT 'mixed' CHECK (gender_policy IN ('mixed','male','female')),
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ward_beds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ward_id UUID NOT NULL REFERENCES public.ward_units(id) ON DELETE CASCADE,
  bed_number TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available','occupied','reserved','cleaning','maintenance','blocked')),
  patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  admission_id UUID,
  occupied_at TIMESTAMPTZ,
  released_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (ward_id, bed_number)
);
CREATE INDEX IF NOT EXISTS idx_ward_beds_status ON public.ward_beds(status, ward_id);
CREATE INDEX IF NOT EXISTS idx_ward_beds_patient ON public.ward_beds(patient_id);

CREATE TABLE IF NOT EXISTS public.nursing_care_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID,
  admission_id UUID,
  problem TEXT NOT NULL,
  goal TEXT NOT NULL,
  interventions TEXT NOT NULL,
  evaluation TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','on_hold','completed','cancelled')),
  priority TEXT NOT NULL DEFAULT 'routine' CHECK (priority IN ('routine','high','critical')),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_nursing_care_plans_patient ON public.nursing_care_plans(patient_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS public.nursing_shift_handovers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  ward_id UUID REFERENCES public.ward_units(id) ON DELETE SET NULL,
  outgoing_officer UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  incoming_officer UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  shift_label TEXT NOT NULL,
  clinical_summary TEXT NOT NULL,
  pending_tasks TEXT,
  safety_concerns TEXT,
  escalation_required BOOLEAN NOT NULL DEFAULT false,
  acknowledged_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_nursing_handover_patient ON public.nursing_shift_handovers(patient_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.emergency_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  arrival_time TIMESTAMPTZ NOT NULL DEFAULT now(),
  arrival_mode TEXT CHECK (arrival_mode IN ('walk_in','ambulance','referral','other')),
  acuity TEXT NOT NULL DEFAULT 'urgent' CHECK (acuity IN ('resuscitation','emergency','urgent','less_urgent','non_urgent')),
  chief_complaint TEXT NOT NULL,
  triage_summary TEXT,
  assigned_officer UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting','triage','treatment','observation','admitted','discharged','referred','left_without_being_seen','cancelled')),
  disposition TEXT,
  disposition_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reconcile the earlier emergency_cases shape (arrival_at/triage_priority/notes)
-- before indexes and workflow policies reference the canonical column names.
ALTER TABLE public.emergency_cases
  ADD COLUMN IF NOT EXISTS arrival_time TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS acuity TEXT,
  ADD COLUMN IF NOT EXISTS triage_summary TEXT,
  ADD COLUMN IF NOT EXISTS disposition_at TIMESTAMPTZ;

DO $emergency_legacy_compat$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='emergency_cases' AND column_name='arrival_at') THEN
    EXECUTE 'UPDATE public.emergency_cases SET arrival_time = COALESCE(arrival_time, arrival_at, created_at, now()) WHERE arrival_time IS NULL';
  ELSE
    UPDATE public.emergency_cases SET arrival_time = COALESCE(arrival_time, created_at, now()) WHERE arrival_time IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='emergency_cases' AND column_name='triage_priority') THEN
    EXECUTE $sql$UPDATE public.emergency_cases
      SET acuity = COALESCE(acuity, CASE triage_priority
        WHEN 'critical' THEN 'resuscitation'
        WHEN 'urgent' THEN 'urgent'
        WHEN 'moderate' THEN 'less_urgent'
        WHEN 'routine' THEN 'non_urgent'
        ELSE 'urgent' END)
      WHERE acuity IS NULL$sql$;
  ELSE
    UPDATE public.emergency_cases SET acuity = COALESCE(acuity, 'urgent') WHERE acuity IS NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='emergency_cases' AND column_name='notes') THEN
    EXECUTE 'UPDATE public.emergency_cases SET triage_summary = COALESCE(triage_summary, notes) WHERE triage_summary IS NULL';
  END IF;
END
$emergency_legacy_compat$;

UPDATE public.emergency_cases
SET arrival_time = COALESCE(arrival_time, created_at, now()),
    acuity = COALESCE(acuity, 'urgent'),
    chief_complaint = COALESCE(NULLIF(trim(chief_complaint), ''), 'Unspecified complaint')
WHERE arrival_time IS NULL OR acuity IS NULL OR chief_complaint IS NULL OR trim(chief_complaint) = '';

ALTER TABLE public.emergency_cases
  ALTER COLUMN arrival_time SET DEFAULT now(),
  ALTER COLUMN arrival_time SET NOT NULL,
  ALTER COLUMN acuity SET DEFAULT 'urgent',
  ALTER COLUMN acuity SET NOT NULL,
  ALTER COLUMN chief_complaint SET NOT NULL;

DO $emergency_check_compat$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.emergency_cases'::regclass AND contype = 'c'
      AND (pg_get_constraintdef(oid) ILIKE '%status%'
        OR pg_get_constraintdef(oid) ILIKE '%arrival_mode%'
        OR pg_get_constraintdef(oid) ILIKE '%acuity%')
  LOOP
    EXECUTE format('ALTER TABLE public.emergency_cases DROP CONSTRAINT %I', c.conname);
  END LOOP;
END
$emergency_check_compat$;

ALTER TABLE public.emergency_cases
  ADD CONSTRAINT emergency_cases_arrival_mode_compat_check
    CHECK (arrival_mode IS NULL OR arrival_mode IN ('walk_in','ambulance','referral','police','other')),
  ADD CONSTRAINT emergency_cases_acuity_compat_check
    CHECK (acuity IN ('resuscitation','emergency','urgent','less_urgent','non_urgent')),
  ADD CONSTRAINT emergency_cases_status_compat_check
    CHECK (status IN ('waiting','triage','treatment','observation','admitted','discharged','referred','left_without_being_seen','cancelled','transferred','deceased'));

CREATE INDEX IF NOT EXISTS idx_emergency_queue ON public.emergency_cases(status, acuity, arrival_time);

CREATE TABLE IF NOT EXISTS public.theatre_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID,
  procedure_name TEXT NOT NULL,
  surgeon_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  anesthetist_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  scheduled_start TIMESTAMPTZ NOT NULL,
  scheduled_end TIMESTAMPTZ,
  theatre_name TEXT,
  urgency TEXT NOT NULL DEFAULT 'elective' CHECK (urgency IN ('emergency','urgent','elective')),
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('requested','approved','scheduled','in_progress','completed','cancelled','postponed')),
  preoperative_notes TEXT,
  postoperative_notes TEXT,
  cancellation_reason TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reconcile legacy theatre/anaesthetist/scheduled_at fields before scheduling indexes.
ALTER TABLE public.theatre_cases
  ADD COLUMN IF NOT EXISTS encounter_id UUID,
  ADD COLUMN IF NOT EXISTS anesthetist_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS scheduled_start TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS scheduled_end TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS theatre_name TEXT,
  ADD COLUMN IF NOT EXISTS urgency TEXT NOT NULL DEFAULT 'elective',
  ADD COLUMN IF NOT EXISTS preoperative_notes TEXT,
  ADD COLUMN IF NOT EXISTS postoperative_notes TEXT,
  ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;

DO $theatre_legacy_compat$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='theatre_cases' AND column_name='anaesthetist_id') THEN
    EXECUTE 'UPDATE public.theatre_cases SET anesthetist_id = COALESCE(anesthetist_id, anaesthetist_id) WHERE anesthetist_id IS NULL';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='theatre_cases' AND column_name='scheduled_at') THEN
    EXECUTE 'UPDATE public.theatre_cases SET scheduled_start = COALESCE(scheduled_start, scheduled_at, created_at, now()) WHERE scheduled_start IS NULL';
  ELSE
    UPDATE public.theatre_cases SET scheduled_start = COALESCE(scheduled_start, created_at, now()) WHERE scheduled_start IS NULL;
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='theatre_cases' AND column_name='theatre') THEN
    EXECUTE 'UPDATE public.theatre_cases SET theatre_name = COALESCE(theatre_name, theatre) WHERE theatre_name IS NULL';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='theatre_cases' AND column_name='notes') THEN
    EXECUTE 'UPDATE public.theatre_cases SET preoperative_notes = COALESCE(preoperative_notes, notes) WHERE preoperative_notes IS NULL';
  END IF;
END
$theatre_legacy_compat$;

UPDATE public.theatre_cases
SET scheduled_start = COALESCE(scheduled_start, created_at, now()),
    status = CASE status WHEN 'planned' THEN 'scheduled' WHEN 'cleared' THEN 'approved' ELSE status END
WHERE scheduled_start IS NULL OR status IN ('planned','cleared');

ALTER TABLE public.theatre_cases
  ALTER COLUMN scheduled_start SET NOT NULL;

DO $theatre_status_compat$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.theatre_cases'::regclass AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.theatre_cases DROP CONSTRAINT %I', c.conname);
  END LOOP;
END
$theatre_status_compat$;

ALTER TABLE public.theatre_cases
  ADD CONSTRAINT theatre_cases_status_compat_check
    CHECK (status IN ('requested','approved','scheduled','in_progress','completed','cancelled','postponed'));

CREATE INDEX IF NOT EXISTS idx_theatre_schedule ON public.theatre_cases(scheduled_start, status);
CREATE INDEX IF NOT EXISTS idx_theatre_patient ON public.theatre_cases(patient_id, scheduled_start DESC);

CREATE TABLE IF NOT EXISTS public.transfusion_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID,
  blood_product TEXT NOT NULL,
  unit_identifier TEXT NOT NULL,
  blood_group TEXT,
  compatibility_checked BOOLEAN NOT NULL DEFAULT false,
  consent_confirmed BOOLEAN NOT NULL DEFAULT false,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  volume_ml NUMERIC CHECK (volume_ml IS NULL OR volume_ml >= 0),
  reaction_observed BOOLEAN NOT NULL DEFAULT false,
  reaction_notes TEXT,
  administered_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  witnessed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','issued','running','completed','stopped','cancelled')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reconcile legacy component/status fields with the canonical transfusion record.
ALTER TABLE public.transfusion_records
  ADD COLUMN IF NOT EXISTS encounter_id UUID,
  ADD COLUMN IF NOT EXISTS blood_product TEXT,
  ADD COLUMN IF NOT EXISTS volume_ml NUMERIC,
  ADD COLUMN IF NOT EXISTS reaction_observed BOOLEAN NOT NULL DEFAULT false;

DO $transfusion_status_compat$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.transfusion_records'::regclass AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.transfusion_records DROP CONSTRAINT %I', c.conname);
  END LOOP;
END
$transfusion_status_compat$;

DO $transfusion_legacy_columns$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='transfusion_records' AND column_name='component') THEN
    EXECUTE 'UPDATE public.transfusion_records SET blood_product = COALESCE(blood_product, component) WHERE blood_product IS NULL';
  END IF;
END
$transfusion_legacy_columns$;

UPDATE public.transfusion_records
SET blood_product = COALESCE(blood_product, 'other'),
    reaction_observed = reaction_observed OR status = 'reaction' OR NULLIF(trim(reaction_notes), '') IS NOT NULL,
    status = CASE status WHEN 'verified' THEN 'issued' WHEN 'reaction' THEN 'stopped' ELSE status END
WHERE blood_product IS NULL OR status IN ('verified','reaction')
   OR (reaction_observed = false AND NULLIF(trim(reaction_notes), '') IS NOT NULL);

ALTER TABLE public.transfusion_records
  ALTER COLUMN blood_product SET NOT NULL,
  ADD CONSTRAINT transfusion_records_status_compat_check
    CHECK (status IN ('planned','issued','running','completed','stopped','cancelled'));

CREATE INDEX IF NOT EXISTS idx_transfusion_patient ON public.transfusion_records(patient_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS uq_active_transfusion_unit ON public.transfusion_records(unit_identifier) WHERE status IN ('issued','running');

CREATE TABLE IF NOT EXISTS public.insurance_claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  invoice_id UUID,
  payer_name TEXT NOT NULL,
  member_number TEXT,
  claim_number TEXT UNIQUE,
  service_from TIMESTAMPTZ,
  service_to TIMESTAMPTZ,
  amount_claimed NUMERIC NOT NULL DEFAULT 0 CHECK (amount_claimed >= 0),
  amount_approved NUMERIC CHECK (amount_approved IS NULL OR amount_approved >= 0),
  amount_paid NUMERIC NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','submitted','acknowledged','under_review','approved','partially_approved','rejected','paid','resubmission_required','voided')),
  rejection_reason TEXT,
  submitted_at TIMESTAMPTZ,
  adjudicated_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_insurance_claims_patient ON public.insurance_claims(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_insurance_claims_status ON public.insurance_claims(status, created_at DESC);

CREATE TABLE IF NOT EXISTS public.insurance_claim_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id UUID NOT NULL REFERENCES public.insurance_claims(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  from_status TEXT,
  to_status TEXT,
  notes TEXT,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_claim_events_claim ON public.insurance_claim_events(claim_id, created_at DESC);

ALTER TABLE public.ward_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ward_beds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nursing_care_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nursing_shift_handovers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.theatre_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transfusion_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurance_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurance_claim_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  CREATE POLICY "ward operations clinical access" ON public.ward_units FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'specialist_nurse'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  CREATE POLICY "ward beds clinical access" ON public.ward_beds FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'specialist_nurse'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  CREATE POLICY "nursing care plan access" ON public.nursing_care_plans FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) WITH CHECK (created_by = auth.uid() OR public.has_role(auth.uid(),'admin'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  CREATE POLICY "nursing handover access" ON public.nursing_shift_handovers FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) WITH CHECK (outgoing_officer = auth.uid() OR incoming_officer = auth.uid() OR public.has_role(auth.uid(),'admin'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  CREATE POLICY "emergency clinical access" ON public.emergency_cases FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'front_desk')) WITH CHECK (assigned_officer = auth.uid() OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'front_desk'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  CREATE POLICY "theatre clinical access" ON public.theatre_cases FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'specialist_nurse')) WITH CHECK (created_by = auth.uid() OR surgeon_id = auth.uid() OR public.has_role(auth.uid(),'admin'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  CREATE POLICY "transfusion clinical access" ON public.transfusion_records FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'specialist_nurse')) WITH CHECK (administered_by = auth.uid() OR witnessed_by = auth.uid() OR public.has_role(auth.uid(),'admin'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  CREATE POLICY "insurance claims accounts access" ON public.insurance_claims FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'practitioner')) WITH CHECK (created_by = auth.uid() OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  CREATE POLICY "insurance claim events read" ON public.insurance_claim_events FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'practitioner'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION public.touch_global_hims_updated_at() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$ BEGIN NEW.updated_at=now(); RETURN NEW; END; $$;
DROP TRIGGER IF EXISTS t_ward_units_updated ON public.ward_units;
CREATE TRIGGER t_ward_units_updated BEFORE UPDATE ON public.ward_units FOR EACH ROW EXECUTE FUNCTION public.touch_global_hims_updated_at();
DROP TRIGGER IF EXISTS t_ward_beds_updated ON public.ward_beds;
CREATE TRIGGER t_ward_beds_updated BEFORE UPDATE ON public.ward_beds FOR EACH ROW EXECUTE FUNCTION public.touch_global_hims_updated_at();
DROP TRIGGER IF EXISTS t_care_plans_updated ON public.nursing_care_plans;
CREATE TRIGGER t_care_plans_updated BEFORE UPDATE ON public.nursing_care_plans FOR EACH ROW EXECUTE FUNCTION public.touch_global_hims_updated_at();
DROP TRIGGER IF EXISTS t_emergency_updated ON public.emergency_cases;
CREATE TRIGGER t_emergency_updated BEFORE UPDATE ON public.emergency_cases FOR EACH ROW EXECUTE FUNCTION public.touch_global_hims_updated_at();
DROP TRIGGER IF EXISTS t_theatre_updated ON public.theatre_cases;
CREATE TRIGGER t_theatre_updated BEFORE UPDATE ON public.theatre_cases FOR EACH ROW EXECUTE FUNCTION public.touch_global_hims_updated_at();
DROP TRIGGER IF EXISTS t_transfusion_updated ON public.transfusion_records;
CREATE TRIGGER t_transfusion_updated BEFORE UPDATE ON public.transfusion_records FOR EACH ROW EXECUTE FUNCTION public.touch_global_hims_updated_at();
DROP TRIGGER IF EXISTS t_claim_updated ON public.insurance_claims;
CREATE TRIGGER t_claim_updated BEFORE UPDATE ON public.insurance_claims FOR EACH ROW EXECUTE FUNCTION public.touch_global_hims_updated_at();

CREATE OR REPLACE FUNCTION public.transition_insurance_claim(_claim_id UUID, _to_status TEXT, _notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE c public.insurance_claims%ROWTYPE; uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN RAISE EXCEPTION 'Accounts role required'; END IF;
  IF _to_status NOT IN ('submitted','acknowledged','under_review','approved','partially_approved','rejected','paid','resubmission_required','voided') THEN RAISE EXCEPTION 'Invalid claim status'; END IF;
  SELECT * INTO c FROM public.insurance_claims WHERE id=_claim_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Claim not found'; END IF;
  UPDATE public.insurance_claims SET status=_to_status, rejection_reason=CASE WHEN _to_status='rejected' THEN _notes ELSE rejection_reason END,
    submitted_at=CASE WHEN _to_status='submitted' AND submitted_at IS NULL THEN now() ELSE submitted_at END,
    adjudicated_at=CASE WHEN _to_status IN ('approved','partially_approved','rejected') THEN now() ELSE adjudicated_at END,
    paid_at=CASE WHEN _to_status='paid' THEN now() ELSE paid_at END WHERE id=_claim_id;
  INSERT INTO public.insurance_claim_events(claim_id,event_type,from_status,to_status,notes,actor_id) VALUES (_claim_id,'status_changed',c.status,_to_status,_notes,uid);
  RETURN jsonb_build_object('claim_id',_claim_id,'status',_to_status);
END; $$;
GRANT EXECUTE ON FUNCTION public.transition_insurance_claim(UUID,TEXT,TEXT) TO authenticated;
