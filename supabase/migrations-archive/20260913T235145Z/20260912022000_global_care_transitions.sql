-- Global care-transition foundation: referrals and structured discharge planning.
CREATE TABLE IF NOT EXISTS public.patient_referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID,
  referred_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  destination TEXT NOT NULL,
  specialty TEXT,
  reason TEXT NOT NULL,
  urgency TEXT NOT NULL DEFAULT 'routine' CHECK (urgency IN ('routine','urgent','emergency')),
  status TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','accepted','scheduled','completed','declined','cancelled')),
  clinical_summary TEXT,
  appointment_date TIMESTAMPTZ,
  receiving_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_patient_referrals_patient ON public.patient_referrals(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_patient_referrals_status ON public.patient_referrals(status, urgency, created_at DESC);

CREATE TABLE IF NOT EXISTS public.care_transitions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  admission_id UUID,
  transition_type TEXT NOT NULL CHECK (transition_type IN ('discharge','transfer','follow_up')),
  status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','ready','completed','cancelled')),
  destination TEXT,
  summary TEXT,
  medications_reconciled BOOLEAN NOT NULL DEFAULT false,
  follow_up_required BOOLEAN NOT NULL DEFAULT false,
  follow_up_date DATE,
  instructions TEXT,
  responsible_officer UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_care_transitions_patient ON public.care_transitions(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_care_transitions_status ON public.care_transitions(status, transition_type);

ALTER TABLE public.patient_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.care_transitions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "care referrals clinical access" ON public.patient_referrals;
CREATE POLICY "care referrals clinical access" ON public.patient_referrals FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'front_desk')) WITH CHECK (referred_by = auth.uid() OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS "care transitions clinical access" ON public.care_transitions;
CREATE POLICY "care transitions clinical access" ON public.care_transitions FOR ALL TO authenticated USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) WITH CHECK (responsible_officer = auth.uid() OR public.has_role(auth.uid(),'admin'));

CREATE OR REPLACE FUNCTION public.touch_care_transition_updated_at() RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public AS $$ BEGIN NEW.updated_at=now(); RETURN NEW; END; $$;
DROP TRIGGER IF EXISTS t_referral_updated_at ON public.patient_referrals;
CREATE TRIGGER t_referral_updated_at BEFORE UPDATE ON public.patient_referrals FOR EACH ROW EXECUTE FUNCTION public.touch_care_transition_updated_at();
DROP TRIGGER IF EXISTS t_transition_updated_at ON public.care_transitions;
CREATE TRIGGER t_transition_updated_at BEFORE UPDATE ON public.care_transitions FOR EACH ROW EXECUTE FUNCTION public.touch_care_transition_updated_at();
