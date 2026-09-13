-- 1. Goods receipt approval workflow
ALTER TABLE public.pharmacy_goods_receipts
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS approved_by uuid,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejection_reason text;

-- Replace trigger function: only apply on approval transition
CREATE OR REPLACE FUNCTION public.apply_goods_receipt()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  -- On INSERT: only apply if already approved
  IF (TG_OP = 'INSERT') THEN
    IF NEW.status = 'approved' AND NEW.inventory_id IS NOT NULL THEN
      UPDATE public.pharmacy_inventory
        SET stock_quantity = stock_quantity + NEW.quantity, updated_at = now()
      WHERE id = NEW.inventory_id;
    END IF;
    RETURN NEW;
  END IF;
  -- On UPDATE: apply only when transitioning into approved
  IF (TG_OP = 'UPDATE') THEN
    IF NEW.status = 'approved' AND COALESCE(OLD.status, '') <> 'approved' AND NEW.inventory_id IS NOT NULL THEN
      UPDATE public.pharmacy_inventory
        SET stock_quantity = stock_quantity + NEW.quantity, updated_at = now()
      WHERE id = NEW.inventory_id;
    END IF;
    RETURN NEW;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS apply_goods_receipt_trg ON public.pharmacy_goods_receipts;
CREATE TRIGGER apply_goods_receipt_trg
AFTER INSERT OR UPDATE ON public.pharmacy_goods_receipts
FOR EACH ROW EXECUTE FUNCTION public.apply_goods_receipt();

-- 2. Medication administrations for dispense/inpatient dosage tracking
CREATE TABLE IF NOT EXISTS public.medication_administrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  prescription_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  inventory_id uuid,
  drug_name text NOT NULL,
  dose text,
  quantity_dispensed integer NOT NULL DEFAULT 1,
  administered_by uuid,
  administered_at timestamptz NOT NULL DEFAULT now(),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.medication_administrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ma_staff_all" ON public.medication_administrations
  FOR ALL TO authenticated
  USING (is_clinical_staff(auth.uid()))
  WITH CHECK (is_clinical_staff(auth.uid()));

CREATE POLICY "ma_patient_read" ON public.medication_administrations
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM patients p WHERE p.id = medication_administrations.patient_id AND p.user_id = auth.uid()));

-- Auto-decrement inventory when administration recorded
CREATE OR REPLACE FUNCTION public.apply_medication_administration()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.inventory_id IS NOT NULL AND NEW.quantity_dispensed > 0 THEN
    UPDATE public.pharmacy_inventory
      SET stock_quantity = GREATEST(0, stock_quantity - NEW.quantity_dispensed),
          updated_at = now()
    WHERE id = NEW.inventory_id;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS apply_med_admin_trg ON public.medication_administrations;
CREATE TRIGGER apply_med_admin_trg
AFTER INSERT ON public.medication_administrations
FOR EACH ROW EXECUTE FUNCTION public.apply_medication_administration();

-- 3. AI report request log (patient-initiated)
CREATE TABLE IF NOT EXISTS public.ai_report_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL,
  requested_by uuid,
  report_type text NOT NULL DEFAULT 'medical_summary',
  status text NOT NULL DEFAULT 'pending',
  content text,
  error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);
ALTER TABLE public.ai_report_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "arr_owner_rw" ON public.ai_report_requests
  FOR ALL TO authenticated
  USING (
    requested_by = auth.uid()
    OR EXISTS (SELECT 1 FROM patients p WHERE p.id = ai_report_requests.patient_id AND p.user_id = auth.uid())
    OR is_clinical_staff(auth.uid())
  )
  WITH CHECK (
    requested_by = auth.uid()
    OR EXISTS (SELECT 1 FROM patients p WHERE p.id = ai_report_requests.patient_id AND p.user_id = auth.uid())
    OR is_clinical_staff(auth.uid())
  );