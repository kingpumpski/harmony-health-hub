-- Harmony Health Hub: workflow completion and international HIMS foundations.
-- This migration is intentionally additive and idempotent so existing deployments can
-- adopt the completed workflow without replacing canonical clinical tables.

-- 1. Extend RBAC for the specialist nurse role.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_role')
     AND NOT EXISTS (
       SELECT 1
       FROM pg_enum e
       JOIN pg_type t ON t.oid = e.enumtypid
       WHERE t.typname = 'app_role' AND e.enumlabel = 'specialist_nurse'
     ) THEN
    ALTER TYPE public.app_role ADD VALUE 'specialist_nurse';
  END IF;
END $$;

-- 2. Facility-level operational settings.
CREATE TABLE IF NOT EXISTS public.facility_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_name TEXT NOT NULL DEFAULT 'Harmony Health Hub',
  country_code CHAR(2) NOT NULL DEFAULT 'GH',
  currency_code CHAR(3) NOT NULL DEFAULT 'GHS',
  timezone TEXT NOT NULL DEFAULT 'Africa/Accra',
  payment_routing_mode TEXT NOT NULL DEFAULT 'streamlined'
    CHECK (payment_routing_mode IN ('pay_before_every_step','streamlined')),
  enable_patient_portal BOOLEAN NOT NULL DEFAULT TRUE,
  enable_ai_decision_support BOOLEAN NOT NULL DEFAULT TRUE,
  default_appointment_minutes INTEGER NOT NULL DEFAULT 30
    CHECK (default_appointment_minutes BETWEEN 5 AND 480),
  updated_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS facility_settings_singleton_idx
  ON public.facility_settings ((true));

INSERT INTO public.facility_settings (facility_name)
SELECT 'Harmony Health Hub'
WHERE NOT EXISTS (SELECT 1 FROM public.facility_settings);

-- 3. Laboratory catalogue and parameter definitions.
CREATE TABLE IF NOT EXISTS public.lab_test_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  category TEXT,
  specimen_type TEXT,
  department TEXT DEFAULT 'laboratory',
  description TEXT,
  interpretation_notes TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.lab_test_parameters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id UUID NOT NULL REFERENCES public.lab_test_catalog(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  value_type TEXT NOT NULL DEFAULT 'numeric'
    CHECK (value_type IN ('numeric','text','boolean','coded')),
  unit TEXT,
  reference_low NUMERIC,
  reference_high NUMERIC,
  reference_text TEXT,
  critical_low NUMERIC,
  critical_high NUMERIC,
  sort_order INTEGER NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (test_id, code)
);

-- Reconcile partially provisioned legacy facility settings before workflows use them.
ALTER TABLE public.facility_settings
  ADD COLUMN IF NOT EXISTS country_code CHAR(2) NOT NULL DEFAULT 'GH',
  ADD COLUMN IF NOT EXISTS currency_code CHAR(3) NOT NULL DEFAULT 'GHS',
  ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'Africa/Accra',
  ADD COLUMN IF NOT EXISTS payment_routing_mode TEXT NOT NULL DEFAULT 'streamlined',
  ADD COLUMN IF NOT EXISTS enable_patient_portal BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS enable_ai_decision_support BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS default_appointment_minutes INTEGER NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES auth.users(id);

-- Reconcile partially provisioned legacy service-order tables before indexing them.
-- CREATE TABLE IF NOT EXISTS does not add columns to an existing legacy table.
ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS ordered_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS service_type TEXT NOT NULL DEFAULT 'general',
  ADD COLUMN IF NOT EXISTS source_id UUID,
  ADD COLUMN IF NOT EXISTS release_reason TEXT,
  ADD COLUMN IF NOT EXISTS released_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS released_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS fulfillment_status TEXT NOT NULL DEFAULT 'blocked',
  ADD COLUMN IF NOT EXISTS priority TEXT NOT NULL DEFAULT 'routine';

-- Normalize recognized legacy routing values without changing facility identity.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'facility_settings' AND column_name = 'routing_mode'
  ) THEN
    EXECUTE $sql$
      UPDATE public.facility_settings
      SET payment_routing_mode = CASE
        WHEN routing_mode IN ('pay_before_each_step','pay_before_every_step','strict') THEN 'pay_before_every_step'
        ELSE 'streamlined'
      END
      WHERE payment_routing_mode = 'streamlined'
    $sql$;
  END IF;
END $$;

-- Preserve the legacy lifecycle when canonical fulfillment state is introduced.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'service_orders' AND column_name = 'status'
  ) THEN
    EXECUTE $sql$
      UPDATE public.service_orders
      SET fulfillment_status = CASE
        WHEN lower(COALESCE(status::text, '')) IN ('released','in_progress','completed','cancelled')
          THEN lower(status::text)
        ELSE fulfillment_status
      END
      WHERE fulfillment_status = 'blocked'
        AND lower(COALESCE(status::text, '')) IN ('released','in_progress','completed','cancelled')
    $sql$;
  END IF;
END $$;

-- Reconcile legacy laboratory catalog columns before indexes and updated_at triggers.
ALTER TABLE public.lab_test_catalog
  ADD COLUMN IF NOT EXISTS specimen_type TEXT,
  ADD COLUMN IF NOT EXISTS department TEXT DEFAULT 'laboratory',
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS interpretation_notes TEXT,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

DO $
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='lab_test_catalog' AND column_name='specimen') THEN
    EXECUTE 'UPDATE public.lab_test_catalog SET specimen_type = COALESCE(specimen_type, specimen) WHERE specimen_type IS NULL';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='lab_test_catalog' AND column_name='notes') THEN
    EXECUTE 'UPDATE public.lab_test_catalog SET description = COALESCE(description, notes) WHERE description IS NULL';
  END IF;
END $;

ALTER TABLE public.lab_test_parameters
  ADD COLUMN IF NOT EXISTS code TEXT,
  ADD COLUMN IF NOT EXISTS value_type TEXT NOT NULL DEFAULT 'numeric',
  ADD COLUMN IF NOT EXISTS reference_low NUMERIC,
  ADD COLUMN IF NOT EXISTS reference_high NUMERIC,
  ADD COLUMN IF NOT EXISTS reference_text TEXT,
  ADD COLUMN IF NOT EXISTS critical_low NUMERIC,
  ADD COLUMN IF NOT EXISTS critical_high NUMERIC,
  ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

DO $
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='lab_test_parameters' AND column_name='ref_low') THEN
    EXECUTE 'UPDATE public.lab_test_parameters SET reference_low = COALESCE(reference_low, ref_low) WHERE reference_low IS NULL';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='lab_test_parameters' AND column_name='ref_high') THEN
    EXECUTE 'UPDATE public.lab_test_parameters SET reference_high = COALESCE(reference_high, ref_high) WHERE reference_high IS NULL';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='lab_test_parameters' AND column_name='ref_text') THEN
    EXECUTE 'UPDATE public.lab_test_parameters SET reference_text = COALESCE(reference_text, ref_text) WHERE reference_text IS NULL';
  END IF;
END $;

-- Reconcile partially provisioned legacy catalog tables before indexing them.
-- CREATE TABLE IF NOT EXISTS does not add columns to an existing table.
ALTER TABLE public.lab_test_parameters
  ADD COLUMN IF NOT EXISTS sort_order INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS lab_test_catalog_active_idx
  ON public.lab_test_catalog (active, category, name);
CREATE INDEX IF NOT EXISTS lab_test_parameters_test_idx
  ON public.lab_test_parameters (test_id, sort_order);

-- 4. Payment-gated service orders. Existing invoices/payments remain canonical financial records.
CREATE TABLE IF NOT EXISTS public.service_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID REFERENCES public.encounters(id) ON DELETE SET NULL,
  ordered_by UUID REFERENCES auth.users(id),
  department TEXT NOT NULL,
  service_type TEXT NOT NULL,
  service_name TEXT NOT NULL,
  source_id UUID,
  amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  payment_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (payment_status IN ('pending','approved','overridden','rejected','waived')),
  fulfillment_status TEXT NOT NULL DEFAULT 'blocked'
    CHECK (fulfillment_status IN ('blocked','released','in_progress','completed','cancelled')),
  priority TEXT NOT NULL DEFAULT 'routine'
    CHECK (priority IN ('routine','urgent','stat')),
  release_reason TEXT,
  released_by UUID REFERENCES auth.users(id),
  released_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS service_orders_queue_idx
  ON public.service_orders (department, fulfillment_status, priority, created_at);
CREATE INDEX IF NOT EXISTS service_orders_patient_idx
  ON public.service_orders (patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS service_orders_payment_idx
  ON public.service_orders (payment_status, fulfillment_status);

-- Server-authoritative service-order state machine. Client-side workflow helpers are advisory;
-- this trigger prevents bypassing payment/release rules through direct database writes.
CREATE OR REPLACE FUNCTION public.validate_service_order_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  routing_mode TEXT;
BEGIN
  SELECT payment_routing_mode INTO routing_mode
  FROM public.facility_settings
  ORDER BY created_at
  LIMIT 1;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.patient_id IS DISTINCT FROM OLD.patient_id
       OR NEW.encounter_id IS DISTINCT FROM OLD.encounter_id
       OR NEW.department IS DISTINCT FROM OLD.department
       OR NEW.service_type IS DISTINCT FROM OLD.service_type
       OR NEW.service_name IS DISTINCT FROM OLD.service_name
       OR NEW.amount IS DISTINCT FROM OLD.amount THEN
      IF OLD.fulfillment_status <> 'blocked' THEN
        RAISE EXCEPTION 'Released service orders cannot change their clinical or financial identity';
      END IF;
    END IF;

    IF NEW.fulfillment_status = 'released' AND OLD.fulfillment_status = 'blocked' THEN
      IF routing_mode = 'pay_before_every_step'
         AND NEW.payment_status NOT IN ('approved','overridden','waived') THEN
        RAISE EXCEPTION 'Payment approval is required before service release';
      END IF;
      IF NEW.payment_status = 'rejected' THEN
        RAISE EXCEPTION 'Rejected service orders cannot be released';
      END IF;
      NEW.released_by := COALESCE(NEW.released_by, auth.uid());
      NEW.released_at := COALESCE(NEW.released_at, now());
    END IF;

    IF OLD.fulfillment_status IN ('completed','cancelled')
       AND NEW.fulfillment_status IS DISTINCT FROM OLD.fulfillment_status THEN
      RAISE EXCEPTION 'Completed or cancelled service orders cannot be reopened';
    END IF;

    IF NEW.fulfillment_status = 'completed' AND OLD.fulfillment_status NOT IN ('in_progress','released') THEN
      RAISE EXCEPTION 'Only released or in-progress service orders can be completed';
    END IF;

    IF NEW.fulfillment_status = 'cancelled' AND OLD.fulfillment_status = 'completed' THEN
      RAISE EXCEPTION 'Completed service orders cannot be cancelled';
    END IF;

    IF NEW.fulfillment_status = 'completed' THEN
      NEW.completed_at := COALESCE(NEW.completed_at, now());
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_service_order_transition ON public.service_orders;
CREATE TRIGGER trg_validate_service_order_transition
BEFORE UPDATE ON public.service_orders
FOR EACH ROW EXECUTE FUNCTION public.validate_service_order_transition();

-- 5. Inpatient continuity extensions. These are additive to the existing admissions model.
CREATE TABLE IF NOT EXISTS public.inpatient_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admission_id UUID NOT NULL REFERENCES public.admissions(id) ON DELETE CASCADE,
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  review_type TEXT NOT NULL DEFAULT 'ward_review',
  reviewed_by UUID REFERENCES auth.users(id),
  reviewer_name TEXT,
  reviewer_role TEXT,
  seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  findings TEXT,
  assessment TEXT,
  plan TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Reconcile the existing Phase 1 inpatient review table before indexing it.
ALTER TABLE public.inpatient_reviews
  ADD COLUMN IF NOT EXISTS seen_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS assessment TEXT;

UPDATE public.inpatient_reviews
SET seen_at = COALESCE(seen_at, created_at, now())
WHERE seen_at IS NULL;

ALTER TABLE public.inpatient_reviews
  ALTER COLUMN seen_at SET DEFAULT now(),
  ALTER COLUMN seen_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS inpatient_reviews_admission_idx
  ON public.inpatient_reviews (admission_id, seen_at DESC);
CREATE INDEX IF NOT EXISTS inpatient_reviews_patient_idx
  ON public.inpatient_reviews (patient_id, seen_at DESC);

-- 6. Patient-level audit history for data changes. Existing application audit remains intact.
CREATE TABLE IF NOT EXISTS public.patient_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  action TEXT NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
  changed_by UUID REFERENCES auth.users(id),
  changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  old_record JSONB,
  new_record JSONB
);

-- Reconcile Phase 1's append-only audit contract with the expanded audit projection.
ALTER TABLE public.patient_audit
  ADD COLUMN IF NOT EXISTS action TEXT NOT NULL DEFAULT 'UPDATE',
  ADD COLUMN IF NOT EXISTS changed_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS changed_at TIMESTAMPTZ NOT NULL DEFAULT now();

UPDATE public.patient_audit
SET changed_by = COALESCE(changed_by, actor_user_id),
    changed_at = COALESCE(changed_at, occurred_at, now()),
    action = COALESCE(action, operation, 'UPDATE')
WHERE changed_by IS NULL OR changed_at IS NULL OR action IS NULL;

CREATE INDEX IF NOT EXISTS patient_audit_patient_idx
  ON public.patient_audit (patient_id, changed_at DESC);

CREATE OR REPLACE FUNCTION public.audit_patient_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.patient_audit (patient_id, action, changed_by, old_record, new_record)
  VALUES (
    COALESCE(NEW.id, OLD.id),
    TG_OP,
    auth.uid(),
    CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END,
    CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) ELSE NULL END
  );
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_patient_audit ON public.patients;
CREATE TRIGGER trg_patient_audit
AFTER INSERT OR UPDATE OR DELETE ON public.patients
FOR EACH ROW EXECUTE FUNCTION public.audit_patient_changes();

-- 7. Generic updated_at helper for new mutable tables.
CREATE OR REPLACE FUNCTION public.touch_hims_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_facility_settings_updated_at ON public.facility_settings;
CREATE TRIGGER trg_facility_settings_updated_at
BEFORE UPDATE ON public.facility_settings
FOR EACH ROW EXECUTE FUNCTION public.touch_hims_updated_at();

DROP TRIGGER IF EXISTS trg_lab_test_catalog_updated_at ON public.lab_test_catalog;
CREATE TRIGGER trg_lab_test_catalog_updated_at
BEFORE UPDATE ON public.lab_test_catalog
FOR EACH ROW EXECUTE FUNCTION public.touch_hims_updated_at();

DROP TRIGGER IF EXISTS trg_lab_test_parameters_updated_at ON public.lab_test_parameters;
CREATE TRIGGER trg_lab_test_parameters_updated_at
BEFORE UPDATE ON public.lab_test_parameters
FOR EACH ROW EXECUTE FUNCTION public.touch_hims_updated_at();

DROP TRIGGER IF EXISTS trg_service_orders_updated_at ON public.service_orders;
CREATE TRIGGER trg_service_orders_updated_at
BEFORE UPDATE ON public.service_orders
FOR EACH ROW EXECUTE FUNCTION public.touch_hims_updated_at();

-- 8. Row-level security for the additive operational tables.
ALTER TABLE public.facility_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_test_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_test_parameters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inpatient_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS facility_settings_staff_read ON public.facility_settings;
CREATE POLICY facility_settings_staff_read
ON public.facility_settings FOR SELECT TO authenticated
USING (public.has_role(auth.uid(), 'admin') OR public.is_clinical_staff(auth.uid()));

DROP POLICY IF EXISTS facility_settings_admin_write ON public.facility_settings;
CREATE POLICY facility_settings_admin_write
ON public.facility_settings FOR ALL TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS lab_catalog_staff_read ON public.lab_test_catalog;
CREATE POLICY lab_catalog_staff_read
ON public.lab_test_catalog FOR SELECT TO authenticated
USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS lab_catalog_admin_write ON public.lab_test_catalog;
CREATE POLICY lab_catalog_admin_write
ON public.lab_test_catalog FOR ALL TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS lab_parameters_staff_read ON public.lab_test_parameters;
CREATE POLICY lab_parameters_staff_read
ON public.lab_test_parameters FOR SELECT TO authenticated
USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS lab_parameters_admin_write ON public.lab_test_parameters;
CREATE POLICY lab_parameters_admin_write
ON public.lab_test_parameters FOR ALL TO authenticated
USING (public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS service_orders_staff_read ON public.service_orders;
CREATE POLICY service_orders_staff_read
ON public.service_orders FOR SELECT TO authenticated
USING (
  public.is_clinical_staff(auth.uid())
  OR public.has_role(auth.uid(), 'accountant')
  OR public.has_role(auth.uid(), 'admin')
  OR patient_id IN (SELECT id FROM public.patients WHERE user_id = auth.uid())
);

DROP POLICY IF EXISTS service_orders_staff_insert ON public.service_orders;
CREATE POLICY service_orders_staff_insert
ON public.service_orders FOR INSERT TO authenticated
WITH CHECK (
  public.is_clinical_staff(auth.uid())
  OR public.has_role(auth.uid(), 'accountant')
  OR public.has_role(auth.uid(), 'admin')
);

DROP POLICY IF EXISTS service_orders_release ON public.service_orders;
CREATE POLICY service_orders_release
ON public.service_orders FOR UPDATE TO authenticated
USING (
  public.has_role(auth.uid(), 'accountant')
  OR public.has_role(auth.uid(), 'admin')
  OR public.is_clinical_staff(auth.uid())
)
WITH CHECK (
  public.has_role(auth.uid(), 'accountant')
  OR public.has_role(auth.uid(), 'admin')
  OR public.is_clinical_staff(auth.uid())
);

DROP POLICY IF EXISTS inpatient_reviews_staff_read ON public.inpatient_reviews;
CREATE POLICY inpatient_reviews_staff_read
ON public.inpatient_reviews FOR SELECT TO authenticated
USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS inpatient_reviews_staff_write ON public.inpatient_reviews;
CREATE POLICY inpatient_reviews_staff_write
ON public.inpatient_reviews FOR ALL TO authenticated
USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(), 'admin'))
WITH CHECK (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS patient_audit_staff_read ON public.patient_audit;
CREATE POLICY patient_audit_staff_read
ON public.patient_audit FOR SELECT TO authenticated
USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(), 'admin'));

-- Audit rows are written only by the SECURITY DEFINER trigger; no direct client insert policy.

COMMENT ON TABLE public.service_orders IS
  'Chargeable clinical services awaiting payment approval or operational release.';
COMMENT ON TABLE public.lab_test_catalog IS
  'Facility laboratory catalogue with reusable test definitions and reference metadata.';
COMMENT ON TABLE public.patient_audit IS
  'Patient row-change history used for clinical accountability and compliance review.';
