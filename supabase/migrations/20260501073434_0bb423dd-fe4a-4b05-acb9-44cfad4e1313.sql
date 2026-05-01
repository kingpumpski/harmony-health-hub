
-- =========================================================
-- ROLES & PROFILES
-- =========================================================
CREATE TYPE public.app_role AS ENUM (
  'admin','practitioner','nurse','midwife','lab_technician',
  'pharmacist','accountant','front_desk','canteen','patient'
);

CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  first_name TEXT,
  last_name TEXT,
  phone TEXT,
  department TEXT,
  specialization TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;

CREATE OR REPLACE FUNCTION public.is_clinical_staff(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
      AND role IN ('admin','practitioner','nurse','midwife','lab_technician','pharmacist','front_desk')
  )
$$;

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, first_name, last_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'first_name',''),
    COALESCE(NEW.raw_user_meta_data->>'last_name','')
  );
  -- Default role: patient (admins can promote later)
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'patient');
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =========================================================
-- PATIENTS
-- =========================================================
CREATE TABLE public.patients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  patient_code TEXT UNIQUE NOT NULL,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  date_of_birth DATE,
  gender TEXT CHECK (gender IN ('male','female','other')),
  phone TEXT,
  email TEXT,
  address TEXT,
  city TEXT,
  ghana_card_number TEXT,
  blood_group TEXT,
  genotype TEXT,
  allergies TEXT,
  chronic_conditions TEXT,
  insurance_provider TEXT,
  insurance_number TEXT,
  emergency_contact_name TEXT,
  emergency_contact_phone TEXT,
  emergency_contact_relation TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ON public.patients(patient_code);
CREATE INDEX ON public.patients(user_id);

-- =========================================================
-- APPOINTMENTS
-- =========================================================
CREATE TABLE public.appointments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  practitioner_id UUID REFERENCES auth.users(id),
  department TEXT,
  scheduled_at TIMESTAMPTZ NOT NULL,
  duration_minutes INT DEFAULT 30,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'scheduled', -- scheduled,checked_in,completed,cancelled,no_show
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================================
-- VITAL SIGNS (triage)
-- =========================================================
CREATE TABLE public.vital_signs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  recorded_by UUID REFERENCES auth.users(id),
  systolic INT,
  diastolic INT,
  pulse_rate INT,
  temperature NUMERIC(4,1),
  respiratory_rate INT,
  oxygen_saturation INT,
  weight_kg NUMERIC(5,2),
  height_cm NUMERIC(5,2),
  bmi NUMERIC(4,1),
  priority TEXT, -- critical,urgent,moderate,routine
  notes TEXT,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================================
-- ENCOUNTERS / CONSULTATIONS
-- =========================================================
CREATE TABLE public.encounters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  practitioner_id UUID REFERENCES auth.users(id),
  encounter_type TEXT DEFAULT 'consultation', -- consultation, specialist, fertility
  symptoms TEXT,
  clerking_notes TEXT,
  principal_diagnosis TEXT,
  treatment_plan TEXT,
  follow_up_date DATE,
  status TEXT NOT NULL DEFAULT 'draft', -- draft, completed
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

CREATE TABLE public.diagnoses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  encounter_id UUID NOT NULL REFERENCES public.encounters(id) ON DELETE CASCADE,
  diagnosis TEXT NOT NULL,
  is_principal BOOLEAN DEFAULT FALSE,
  icd_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.prescriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  encounter_id UUID REFERENCES public.encounters(id) ON DELETE CASCADE,
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  prescribed_by UUID REFERENCES auth.users(id),
  medication TEXT NOT NULL,
  dosage TEXT,
  frequency TEXT,
  duration TEXT,
  instructions TEXT,
  status TEXT NOT NULL DEFAULT 'pending', -- pending, dispensed, cancelled
  dispensed_by UUID REFERENCES auth.users(id),
  dispensed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================================
-- LABORATORY
-- =========================================================
CREATE TABLE public.lab_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID REFERENCES public.encounters(id) ON DELETE SET NULL,
  ordered_by UUID REFERENCES auth.users(id),
  test_name TEXT NOT NULL,
  test_category TEXT,
  priority TEXT DEFAULT 'routine', -- routine, urgent, stat
  clinical_notes TEXT,
  status TEXT NOT NULL DEFAULT 'ordered',
  -- ordered, sample_collected, in_progress, completed, approved, cancelled
  sample_collected_at TIMESTAMPTZ,
  collected_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.lab_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_order_id UUID NOT NULL REFERENCES public.lab_orders(id) ON DELETE CASCADE,
  result_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  interpretation TEXT,
  is_abnormal BOOLEAN DEFAULT FALSE,
  entered_by UUID REFERENCES auth.users(id),
  entered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'draft', -- draft, completed, approved
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================================
-- BILLING
-- =========================================================
CREATE TABLE public.invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number TEXT UNIQUE NOT NULL,
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID REFERENCES public.encounters(id) ON DELETE SET NULL,
  total_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
  paid_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
  outstanding_amount NUMERIC(10,2) GENERATED ALWAYS AS (total_amount - paid_amount) STORED,
  insurance_covered NUMERIC(10,2) DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending', -- pending, partially_paid, paid, cancelled
  notes TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.invoice_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  quantity INT NOT NULL DEFAULT 1,
  unit_price NUMERIC(10,2) NOT NULL,
  amount NUMERIC(10,2) NOT NULL,
  category TEXT, -- consultation, lab, pharmacy, procedure, ward
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID REFERENCES public.invoices(id) ON DELETE SET NULL,
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL,
  method TEXT, -- cash, card, mobile_money, insurance, advance
  reference TEXT,
  received_by UUID REFERENCES auth.users(id),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.insurance_claims (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  policy_number TEXT,
  amount_claimed NUMERIC(10,2) NOT NULL,
  amount_approved NUMERIC(10,2),
  status TEXT NOT NULL DEFAULT 'submitted', -- submitted, approved, rejected, paid
  notes TEXT,
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ
);

-- Auto-recompute invoice paid_amount/status when payments change
CREATE OR REPLACE FUNCTION public.refresh_invoice_totals()
RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
DECLARE
  inv_id UUID;
  total_paid NUMERIC(10,2);
  inv_total NUMERIC(10,2);
BEGIN
  inv_id := COALESCE(NEW.invoice_id, OLD.invoice_id);
  IF inv_id IS NULL THEN RETURN NEW; END IF;

  SELECT COALESCE(SUM(amount),0) INTO total_paid
  FROM public.payments WHERE invoice_id = inv_id;

  SELECT total_amount INTO inv_total FROM public.invoices WHERE id = inv_id;

  UPDATE public.invoices
  SET paid_amount = total_paid,
      status = CASE
        WHEN total_paid <= 0 THEN 'pending'
        WHEN total_paid < inv_total THEN 'partially_paid'
        ELSE 'paid'
      END,
      updated_at = now()
  WHERE id = inv_id;

  RETURN NEW;
END;
$$;

CREATE TRIGGER payments_refresh_invoice
AFTER INSERT OR UPDATE OR DELETE ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.refresh_invoice_totals();

-- =========================================================
-- FERTILITY CLINIC
-- =========================================================
CREATE TABLE public.fertility_cycles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  partner_name TEXT,
  cycle_type TEXT NOT NULL, -- IVF, IUI, ICSI, FET
  cycle_number INT DEFAULT 1,
  start_date DATE NOT NULL,
  expected_retrieval_date DATE,
  expected_transfer_date DATE,
  protocol TEXT,
  status TEXT NOT NULL DEFAULT 'active', -- active, completed, cancelled, successful, unsuccessful
  outcome TEXT,
  assigned_specialist UUID REFERENCES auth.users(id),
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.fertility_monitoring (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id UUID NOT NULL REFERENCES public.fertility_cycles(id) ON DELETE CASCADE,
  visit_date DATE NOT NULL,
  cycle_day INT,
  estradiol NUMERIC(10,2),
  lh NUMERIC(10,2),
  fsh NUMERIC(10,2),
  progesterone NUMERIC(10,2),
  follicle_count_left INT,
  follicle_count_right INT,
  endometrial_thickness NUMERIC(4,1),
  medication_adjustments TEXT,
  notes TEXT,
  recorded_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================================
-- TELEMEDICINE
-- =========================================================
CREATE TABLE public.video_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  practitioner_id UUID REFERENCES auth.users(id),
  room_name TEXT NOT NULL,
  provider TEXT DEFAULT 'daily', -- daily, livekit, twilio
  scheduled_at TIMESTAMPTZ NOT NULL,
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'scheduled', -- scheduled, active, completed, cancelled
  payment_required BOOLEAN DEFAULT TRUE,
  payment_received BOOLEAN DEFAULT FALSE,
  recording_url TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================================
-- updated_at triggers
-- =========================================================
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER LANGUAGE PLPGSQL AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER t_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER t_patients_updated BEFORE UPDATE ON public.patients FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER t_appointments_updated BEFORE UPDATE ON public.appointments FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER t_encounters_updated BEFORE UPDATE ON public.encounters FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER t_lab_orders_updated BEFORE UPDATE ON public.lab_orders FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER t_lab_results_updated BEFORE UPDATE ON public.lab_results FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER t_invoices_updated BEFORE UPDATE ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();
CREATE TRIGGER t_fertility_cycles_updated BEFORE UPDATE ON public.fertility_cycles FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- =========================================================
-- ENABLE RLS
-- =========================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vital_signs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.encounters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnoses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prescriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.insurance_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fertility_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fertility_monitoring ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_sessions ENABLE ROW LEVEL SECURITY;

-- =========================================================
-- POLICIES
-- =========================================================

-- profiles
CREATE POLICY "users read own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "staff read all profiles" ON public.profiles FOR SELECT USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'admin'));
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "admins manage profiles" ON public.profiles FOR ALL USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

-- user_roles
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "admins read all roles" ON public.user_roles FOR SELECT USING (public.has_role(auth.uid(),'admin'));
CREATE POLICY "admins manage roles" ON public.user_roles FOR ALL USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

-- patients
CREATE POLICY "patient reads own record" ON public.patients FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "staff read patients" ON public.patients FOR SELECT USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'accountant'));
CREATE POLICY "staff create patients" ON public.patients FOR INSERT WITH CHECK (public.is_clinical_staff(auth.uid()));
CREATE POLICY "staff update patients" ON public.patients FOR UPDATE USING (public.is_clinical_staff(auth.uid()));
CREATE POLICY "admins delete patients" ON public.patients FOR DELETE USING (public.has_role(auth.uid(),'admin'));

-- helper macro pattern: patient-scoped tables
-- appointments
CREATE POLICY "patient reads own appts" ON public.appointments FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid())
);
CREATE POLICY "staff read appts" ON public.appointments FOR SELECT USING (public.is_clinical_staff(auth.uid()));
CREATE POLICY "staff write appts" ON public.appointments FOR ALL USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

-- vital_signs
CREATE POLICY "patient reads own vitals" ON public.vital_signs FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid())
);
CREATE POLICY "staff manage vitals" ON public.vital_signs FOR ALL USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

-- encounters
CREATE POLICY "patient reads own encounters" ON public.encounters FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid())
);
CREATE POLICY "staff manage encounters" ON public.encounters FOR ALL USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

-- diagnoses
CREATE POLICY "patient reads own diagnoses" ON public.diagnoses FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.encounters e
    JOIN public.patients p ON p.id = e.patient_id
    WHERE e.id = encounter_id AND p.user_id = auth.uid()
  )
);
CREATE POLICY "staff manage diagnoses" ON public.diagnoses FOR ALL USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

-- prescriptions
CREATE POLICY "patient reads own rx" ON public.prescriptions FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid())
);
CREATE POLICY "staff manage rx" ON public.prescriptions FOR ALL USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

-- lab_orders
CREATE POLICY "patient reads own lab orders" ON public.lab_orders FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid())
);
CREATE POLICY "staff manage lab orders" ON public.lab_orders FOR ALL USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

-- lab_results
CREATE POLICY "patient reads own results" ON public.lab_results FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.lab_orders o
    JOIN public.patients p ON p.id = o.patient_id
    WHERE o.id = lab_order_id AND p.user_id = auth.uid()
  )
);
CREATE POLICY "staff manage lab results" ON public.lab_results FOR ALL USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

-- invoices / items / payments / claims
CREATE POLICY "patient reads own invoices" ON public.invoices FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid())
);
CREATE POLICY "billing reads invoices" ON public.invoices FOR SELECT USING (public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'front_desk'));
CREATE POLICY "billing manage invoices" ON public.invoices FOR ALL USING (public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'front_desk')) WITH CHECK (public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'front_desk'));

CREATE POLICY "patient reads own invoice items" ON public.invoice_items FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.invoices i
    JOIN public.patients p ON p.id = i.patient_id
    WHERE i.id = invoice_id AND p.user_id = auth.uid()
  )
);
CREATE POLICY "billing manage invoice items" ON public.invoice_items FOR ALL USING (public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'front_desk')) WITH CHECK (public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'front_desk'));

CREATE POLICY "patient reads own payments" ON public.payments FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid())
);
CREATE POLICY "billing manage payments" ON public.payments FOR ALL USING (public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'front_desk')) WITH CHECK (public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'front_desk'));

CREATE POLICY "billing manage claims" ON public.insurance_claims FOR ALL USING (public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'admin'));
CREATE POLICY "patient reads own claims" ON public.insurance_claims FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid())
);

-- fertility
CREATE POLICY "patient reads own cycles" ON public.fertility_cycles FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid())
);
CREATE POLICY "staff manage cycles" ON public.fertility_cycles FOR ALL USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

CREATE POLICY "patient reads own monitoring" ON public.fertility_monitoring FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.fertility_cycles c
    JOIN public.patients p ON p.id = c.patient_id
    WHERE c.id = cycle_id AND p.user_id = auth.uid()
  )
);
CREATE POLICY "staff manage monitoring" ON public.fertility_monitoring FOR ALL USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));

-- video_sessions
CREATE POLICY "patient reads own sessions" ON public.video_sessions FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.patients p WHERE p.id = patient_id AND p.user_id = auth.uid())
);
CREATE POLICY "staff manage sessions" ON public.video_sessions FOR ALL USING (public.is_clinical_staff(auth.uid())) WITH CHECK (public.is_clinical_staff(auth.uid()));
