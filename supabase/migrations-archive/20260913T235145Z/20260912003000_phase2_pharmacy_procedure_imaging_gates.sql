-- Phase 2 completion: pharmacy/procedure enforcement + imaging workflow.
-- Extends existing schema; does not recreate legacy service-order tables.

ALTER TABLE public.procedure_notes
  ADD COLUMN IF NOT EXISTS charge_amount NUMERIC NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS public.imaging_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id UUID NULL REFERENCES public.encounters(id) ON DELETE SET NULL,
  modality TEXT NOT NULL,
  study_name TEXT NOT NULL,
  body_site TEXT,
  priority TEXT NOT NULL DEFAULT 'routine',
  clinical_indication TEXT,
  amount NUMERIC NOT NULL DEFAULT 0 CHECK (amount >= 0),
  status TEXT NOT NULL DEFAULT 'pending_payment_approval'
    CHECK (status IN ('pending_payment_approval','released','in_progress','completed','cancelled')),
  service_order_id UUID NULL REFERENCES public.service_orders(id) ON DELETE SET NULL,
  requested_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  performed_by UUID NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  report TEXT,
  impression TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_imaging_orders_patient ON public.imaging_orders(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_imaging_orders_status ON public.imaging_orders(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_imaging_orders_service_order ON public.imaging_orders(service_order_id);

DROP TRIGGER IF EXISTS imaging_orders_updated_at ON public.imaging_orders;
CREATE TRIGGER imaging_orders_updated_at
BEFORE UPDATE ON public.imaging_orders
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER TABLE public.imaging_orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS imaging_orders_clinical_read ON public.imaging_orders;
CREATE POLICY imaging_orders_clinical_read
ON public.imaging_orders FOR SELECT TO authenticated
USING (public.is_clinical_staff(auth.uid()) OR patient_id = auth.uid());

DROP POLICY IF EXISTS imaging_orders_clinical_insert ON public.imaging_orders;
CREATE POLICY imaging_orders_clinical_insert
ON public.imaging_orders FOR INSERT TO authenticated
WITH CHECK (public.is_clinical_staff(auth.uid()) AND requested_by = auth.uid());

DROP POLICY IF EXISTS imaging_orders_clinical_update ON public.imaging_orders;
CREATE POLICY imaging_orders_clinical_update
ON public.imaging_orders FOR UPDATE TO authenticated
USING (public.is_clinical_staff(auth.uid()))
WITH CHECK (public.is_clinical_staff(auth.uid()));

CREATE OR REPLACE FUNCTION public.create_imaging_order_with_payment_gate(
  _patient_id UUID,
  _encounter_id UUID DEFAULT NULL,
  _modality TEXT DEFAULT 'X-Ray',
  _study_name TEXT DEFAULT 'General study',
  _body_site TEXT DEFAULT NULL,
  _priority TEXT DEFAULT 'routine',
  _clinical_indication TEXT DEFAULT NULL,
  _amount NUMERIC DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_imaging_id UUID;
  v_service_id UUID;
  v_status TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_study_name), '') IS NULL THEN
    RAISE EXCEPTION 'Patient and study name are required';
  END IF;
  IF COALESCE(_amount, 0) < 0 THEN RAISE EXCEPTION 'Amount cannot be negative'; END IF;

  INSERT INTO public.imaging_orders (
    patient_id, encounter_id, modality, study_name, body_site, priority,
    clinical_indication, amount, status, requested_by
  ) VALUES (
    _patient_id, _encounter_id, trim(_modality), trim(_study_name), NULLIF(trim(_body_site), ''),
    COALESCE(NULLIF(trim(_priority), ''), 'routine'), NULLIF(trim(_clinical_indication), ''),
    COALESCE(_amount, 0), CASE WHEN COALESCE(_amount, 0) > 0 THEN 'pending_payment_approval' ELSE 'released' END,
    v_uid
  ) RETURNING id, status INTO v_imaging_id, v_status;

  IF COALESCE(_amount, 0) > 0 THEN
    INSERT INTO public.service_orders (
      patient_id, encounter_id, department, service_name, amount, status,
      requested_by, related_entity_id, order_type, service_code, payment_required, created_by, notes
    ) VALUES (
      _patient_id, _encounter_id, 'imaging', trim(_study_name), COALESCE(_amount, 0),
      'pending_payment_approval', v_uid, v_imaging_id, 'imaging', upper(trim(_modality)), true, v_uid,
      NULLIF(trim(_clinical_indication), '')
    ) RETURNING id INTO v_service_id;

    UPDATE public.imaging_orders SET service_order_id = v_service_id WHERE id = v_imaging_id;
  END IF;

  RETURN jsonb_build_object('imaging_order_id', v_imaging_id, 'service_order_id', v_service_id, 'status', v_status);
END;
$$;

REVOKE ALL ON FUNCTION public.create_imaging_order_with_payment_gate(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_imaging_order_with_payment_gate(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC) TO authenticated;

CREATE OR REPLACE FUNCTION public.enforce_service_payment_gate()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_amount NUMERIC := 0;
  v_related_id UUID;
  v_department TEXT;
  v_status TEXT;
BEGIN
  IF TG_TABLE_NAME = 'procedure_notes' THEN
    v_amount := COALESCE(NEW.charge_amount, 0);
    v_related_id := NEW.id;
    v_department := 'procedure';
  ELSIF TG_TABLE_NAME = 'medication_administrations' THEN
    SELECT COALESCE(pi.unit_price, 0) * COALESCE(NEW.quantity_dispensed, 0)
      INTO v_amount
      FROM public.pharmacy_inventory pi
     WHERE pi.id = NEW.inventory_id;
    v_related_id := NEW.prescription_id;
    v_department := 'pharmacy';
  ELSE
    RETURN NEW;
  END IF;

  IF COALESCE(v_amount, 0) <= 0 THEN RETURN NEW; END IF;

  SELECT so.status INTO v_status
    FROM public.service_orders so
   WHERE so.related_entity_id = v_related_id
     AND so.department = v_department
     AND so.status <> 'cancelled'
   ORDER BY so.created_at DESC
   LIMIT 1;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Payment approval required before % can proceed', v_department;
  END IF;

  IF v_status NOT IN ('released', 'in_progress', 'completed') THEN
    RAISE EXCEPTION 'Payment approval required before % can proceed (status: %)', v_department, v_status;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS procedure_notes_payment_gate ON public.procedure_notes;
CREATE TRIGGER procedure_notes_payment_gate
BEFORE INSERT ON public.procedure_notes
FOR EACH ROW EXECUTE FUNCTION public.enforce_service_payment_gate();

DROP TRIGGER IF EXISTS medication_administrations_payment_gate ON public.medication_administrations;
CREATE TRIGGER medication_administrations_payment_gate
BEFORE INSERT ON public.medication_administrations
FOR EACH ROW EXECUTE FUNCTION public.enforce_service_payment_gate();

COMMENT ON COLUMN public.procedure_notes.charge_amount IS 'Charge in facility currency; chargeable procedures require an approved service_order before the note can be saved.';
COMMENT ON TABLE public.imaging_orders IS 'Diagnostic imaging orders linked to the central payment-gated service workflow.';
