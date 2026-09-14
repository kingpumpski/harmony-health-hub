-- Keep production contracts resilient to explicit NULL invoice numbers and stale PostgREST schema cache.
CREATE OR REPLACE FUNCTION public.generate_invoice_number()
RETURNS text LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  RETURN 'INV-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS') || '-' || substr(gen_random_uuid()::text,1,6);
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_invoice_number()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
BEGIN
  IF NEW.invoice_number IS NULL OR btrim(NEW.invoice_number)='' THEN
    NEW.invoice_number := public.generate_invoice_number();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS invoices_ensure_invoice_number ON public.invoices;
CREATE TRIGGER invoices_ensure_invoice_number
BEFORE INSERT OR UPDATE OF invoice_number ON public.invoices
FOR EACH ROW EXECUTE FUNCTION public.ensure_invoice_number();
ALTER TABLE public.invoices ALTER COLUMN invoice_number SET DEFAULT public.generate_invoice_number();

DROP FUNCTION IF EXISTS public.prepare_patient_billable_items(uuid,timestamptz,timestamptz);
CREATE FUNCTION public.prepare_patient_billable_items(_patient_id uuid,_from timestamptz,_to timestamptz)
RETURNS TABLE(invoice_id uuid,invoice_item_id uuid,source_type text,source_id uuid,description text,category text,department text,quantity integer,unit_price numeric,amount numeric,paid_amount numeric,outstanding_amount numeric,service_order_id uuid,service_order_status text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_invoice uuid; v_invoice_number text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife')) THEN RAISE EXCEPTION 'Billing access required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  SELECT i.id INTO v_invoice FROM public.invoices i WHERE i.patient_id=_patient_id AND i.status NOT IN ('paid','cancelled') ORDER BY i.created_at DESC LIMIT 1;
  IF v_invoice IS NULL THEN
    v_invoice_number:=COALESCE(NULLIF(btrim(public.generate_invoice_number()),''),'INV-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')||'-'||substr(gen_random_uuid()::text,1,6));
    INSERT INTO public.invoices(invoice_number,patient_id,total_amount,paid_amount,status,created_by) VALUES(v_invoice_number,_patient_id,0,0,'pending',auth.uid()) RETURNING id INTO v_invoice;
  END IF;
  RETURN QUERY SELECT ii.invoice_id,ii.id,ii.source_type,ii.source_id,ii.description,ii.category,ii.department,ii.quantity,ii.unit_price,ii.amount,COALESCE(ii.paid_amount,0),GREATEST(ii.amount-COALESCE(ii.paid_amount,0),0),ii.service_order_id,so.status FROM public.invoice_items ii LEFT JOIN public.service_orders so ON so.id=ii.service_order_id WHERE ii.invoice_id=v_invoice AND ii.created_at BETWEEN _from AND _to ORDER BY ii.created_at;
END;
$$;
REVOKE ALL ON FUNCTION public.prepare_patient_billable_items(uuid,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prepare_patient_billable_items(uuid,timestamptz,timestamptz) TO authenticated;

ALTER TABLE public.theatre_cases ADD COLUMN IF NOT EXISTS theatre_name text;
ALTER TABLE public.theatre_cases ADD COLUMN IF NOT EXISTS anesthetist_id uuid;
ALTER TABLE public.theatre_cases ADD COLUMN IF NOT EXISTS scheduled_start timestamptz;
UPDATE public.theatre_cases SET theatre_name=COALESCE(theatre_name,theatre),anesthetist_id=COALESCE(anesthetist_id,anaesthetist_id),scheduled_start=COALESCE(scheduled_start,scheduled_at) WHERE theatre_name IS NULL OR anesthetist_id IS NULL OR scheduled_start IS NULL;
ALTER TABLE public.nursing_shift_handovers ADD COLUMN IF NOT EXISTS pending_tasks text;
ALTER TABLE public.nursing_shift_handovers ADD COLUMN IF NOT EXISTS safety_concerns text;
ALTER TABLE public.nursing_shift_handovers ADD COLUMN IF NOT EXISTS shift_label text;
UPDATE public.nursing_shift_handovers SET pending_tasks=COALESCE(pending_tasks,outstanding_tasks),safety_concerns=COALESCE(safety_concerns,risks_and_alerts),shift_label=COALESCE(shift_label,shift_name) WHERE pending_tasks IS NULL OR safety_concerns IS NULL OR shift_label IS NULL;
ALTER TABLE public.insurance_claims ADD COLUMN IF NOT EXISTS payer_name text;
ALTER TABLE public.insurance_claims ADD COLUMN IF NOT EXISTS member_number text;
ALTER TABLE public.insurance_claims ADD COLUMN IF NOT EXISTS claim_number text;
ALTER TABLE public.insurance_claims ADD COLUMN IF NOT EXISTS amount_paid numeric NOT NULL DEFAULT 0;
ALTER TABLE public.insurance_claims ADD COLUMN IF NOT EXISTS rejection_reason text;
ALTER TABLE public.insurance_claims ADD COLUMN IF NOT EXISTS service_from timestamptz;
ALTER TABLE public.insurance_claims ADD COLUMN IF NOT EXISTS service_to timestamptz;
UPDATE public.insurance_claims SET payer_name=COALESCE(payer_name,provider),member_number=COALESCE(member_number,policy_number),amount_paid=COALESCE(amount_paid,0) WHERE payer_name IS NULL OR member_number IS NULL OR amount_paid IS NULL;
NOTIFY pgrst,'reload schema';
