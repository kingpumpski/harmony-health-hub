-- Reconcile the live database with the application data contract.
-- This migration is additive and preserves existing columns/data.

CREATE OR REPLACE FUNCTION public.generate_invoice_number()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SET search_path TO 'public'
AS $$
BEGIN
  RETURN 'INV-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS') || '-' || substr(gen_random_uuid()::text,1,6);
END;
$$;

ALTER TABLE public.invoices
  ALTER COLUMN invoice_number SET DEFAULT public.generate_invoice_number();

ALTER TABLE public.theatre_cases
  ADD COLUMN IF NOT EXISTS scheduled_start timestamptz;

UPDATE public.theatre_cases
SET scheduled_start = scheduled_at
WHERE scheduled_start IS NULL AND scheduled_at IS NOT NULL;

ALTER TABLE public.nursing_shift_handovers
  ADD COLUMN IF NOT EXISTS shift_label text,
  ADD COLUMN IF NOT EXISTS pending_tasks text,
  ADD COLUMN IF NOT EXISTS safety_concerns text;

UPDATE public.nursing_shift_handovers
SET shift_label = COALESCE(shift_label, shift_name, 'general'),
    pending_tasks = COALESCE(pending_tasks, outstanding_tasks),
    safety_concerns = COALESCE(safety_concerns, risks_and_alerts)
WHERE shift_label IS NULL OR pending_tasks IS NULL OR safety_concerns IS NULL;

ALTER TABLE public.insurance_claims
  ADD COLUMN IF NOT EXISTS payer_name text,
  ADD COLUMN IF NOT EXISTS member_number text,
  ADD COLUMN IF NOT EXISTS claim_number text,
  ADD COLUMN IF NOT EXISTS amount_paid numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS service_from timestamptz,
  ADD COLUMN IF NOT EXISTS service_to timestamptz;

ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS invoice_id uuid,
  ADD COLUMN IF NOT EXISTS invoice_item_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='invoices_patient_id_fkey') THEN
    ALTER TABLE public.invoices ADD CONSTRAINT invoices_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='service_orders_patient_id_fkey') THEN
    ALTER TABLE public.service_orders ADD CONSTRAINT service_orders_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='prescriptions_patient_id_fkey') THEN
    ALTER TABLE public.prescriptions ADD CONSTRAINT prescriptions_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='insurance_claims_patient_id_fkey') THEN
    ALTER TABLE public.insurance_claims ADD CONSTRAINT insurance_claims_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='insurance_claims_invoice_id_fkey') THEN
    ALTER TABLE public.insurance_claims ADD CONSTRAINT insurance_claims_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='service_orders_invoice_id_fkey') THEN
    ALTER TABLE public.service_orders ADD CONSTRAINT service_orders_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES public.invoices(id) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='service_orders_invoice_item_id_fkey') THEN
    ALTER TABLE public.service_orders ADD CONSTRAINT service_orders_invoice_item_id_fkey FOREIGN KEY (invoice_item_id) REFERENCES public.invoice_items(id) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='theatre_cases_patient_id_fkey') THEN
    ALTER TABLE public.theatre_cases ADD CONSTRAINT theatre_cases_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='nursing_shift_handovers_patient_id_fkey') THEN
    ALTER TABLE public.nursing_shift_handovers ADD CONSTRAINT nursing_shift_handovers_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) NOT VALID;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.prepare_patient_billable_items(_patient_id uuid, _from timestamptz, _to timestamptz)
RETURNS TABLE(invoice_id uuid, invoice_item_id uuid, source_type text, source_id uuid, description text, category text, department text, quantity integer, unit_price numeric, amount numeric, paid_amount numeric, outstanding_amount numeric, service_order_id uuid, service_order_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_invoice uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Billing access required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  SELECT i.id INTO v_invoice FROM public.invoices i WHERE i.patient_id=_patient_id AND i.status NOT IN ('paid','cancelled') ORDER BY i.created_at DESC LIMIT 1;
  IF v_invoice IS NULL THEN
    INSERT INTO public.invoices(invoice_number,patient_id,total_amount,paid_amount,status,created_by)
    VALUES(public.generate_invoice_number(),_patient_id,0,0,'pending',auth.uid())
    RETURNING id INTO v_invoice;
  END IF;
  RETURN QUERY
  SELECT ii.invoice_id,ii.id,ii.source_type,ii.source_id,ii.description,ii.category,ii.department,ii.quantity,ii.unit_price,ii.amount,COALESCE(ii.paid_amount,0),GREATEST(ii.amount-COALESCE(ii.paid_amount,0),0),ii.service_order_id,so.status
  FROM public.invoice_items ii
  LEFT JOIN public.service_orders so ON so.id=ii.service_order_id
  WHERE ii.invoice_id=v_invoice AND ii.created_at BETWEEN _from AND _to
  ORDER BY ii.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_patient_billable_items(uuid,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prepare_patient_billable_items(uuid,timestamptz,timestamptz) TO authenticated;

GRANT EXECUTE ON FUNCTION public.notify_due_medications() TO authenticated;
GRANT EXECUTE ON FUNCTION public.lock_overdue_medication_slots() TO authenticated;

NOTIFY pgrst, 'reload schema';
