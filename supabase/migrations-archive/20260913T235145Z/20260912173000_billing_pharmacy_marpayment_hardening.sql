-- Billing, walk-in/temporary membership, pharmacy quantity and MAR controls.
-- Additive/idempotent: extends the existing legacy billing/workflow model.

ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS membership_type TEXT NOT NULL DEFAULT 'permanent'
    CHECK (membership_type IN ('permanent','temporary')),
  ADD COLUMN IF NOT EXISTS membership_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS registration_reason TEXT;
CREATE INDEX IF NOT EXISTS idx_patients_membership_type ON public.patients(membership_type, membership_expires_at);

CREATE TABLE IF NOT EXISTS public.service_tariffs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_code TEXT NOT NULL UNIQUE,
  service_name TEXT NOT NULL,
  category TEXT NOT NULL,
  department TEXT NOT NULL,
  unit TEXT NOT NULL DEFAULT 'each',
  amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  active BOOLEAN NOT NULL DEFAULT true,
  notes TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO public.service_tariffs(service_code,service_name,category,department,unit)
VALUES
 ('CONSULTATION','General consultation','consultation','consultation','visit'),
 ('LAB-GENERIC','Laboratory examination','lab','laboratory','test'),
 ('IMAGING-GENERIC','Diagnostic imaging','imaging','imaging','examination'),
 ('WARD-ACCOM','Accommodation / detention','ward','other','day'),
 ('MEAL','Patient feeding','feeding','canteen','meal'),
 ('PROCEDURE-GENERIC','Other medical service / procedure','procedure','procedure','service')
ON CONFLICT(service_code) DO NOTHING;

ALTER TABLE public.invoice_items
  ADD COLUMN IF NOT EXISTS source_type TEXT,
  ADD COLUMN IF NOT EXISTS source_id UUID,
  ADD COLUMN IF NOT EXISTS source_key TEXT,
  ADD COLUMN IF NOT EXISTS service_code TEXT,
  ADD COLUMN IF NOT EXISTS department TEXT,
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paid_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_invoice_items_source_key
  ON public.invoice_items(source_key) WHERE source_key IS NOT NULL;

ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS invoice_item_id UUID REFERENCES public.invoice_items(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS service_code TEXT;
CREATE INDEX IF NOT EXISTS idx_service_orders_invoice_item ON public.service_orders(invoice_item_id);

CREATE TABLE IF NOT EXISTS public.invoice_item_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_item_id UUID NOT NULL REFERENCES public.invoice_items(id) ON DELETE CASCADE,
  payment_id UUID NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(invoice_item_id, payment_id)
);
ALTER TABLE public.invoice_item_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "invoice item payments staff access" ON public.invoice_item_payments;
CREATE POLICY "invoice item payments staff access" ON public.invoice_item_payments
FOR ALL TO authenticated
USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk'))
WITH CHECK (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk'));

-- Returns the patient's open billable items for a selected period. It also materialises
-- newly discovered clinical events into the patient's open invoice, so refreshes do not duplicate them.
CREATE OR REPLACE FUNCTION public.prepare_patient_billable_items(
  _patient_id UUID,
  _from TIMESTAMPTZ DEFAULT date_trunc('day', now()),
  _to TIMESTAMPTZ DEFAULT now()
)
RETURNS TABLE(
  invoice_id UUID,
  invoice_item_id UUID,
  source_type TEXT,
  source_id UUID,
  description TEXT,
  category TEXT,
  department TEXT,
  quantity INTEGER,
  unit_price NUMERIC,
  amount NUMERIC,
  paid_amount NUMERIC,
  outstanding_amount NUMERIC,
  service_order_id UUID,
  service_order_status TEXT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  inv UUID;
  tariff NUMERIC;
  r RECORD;
  days_count INTEGER;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN
    RAISE EXCEPTION 'Billing access denied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  SELECT id INTO inv FROM public.invoices
  WHERE patient_id = _patient_id AND status IN ('pending','partially_paid')
  ORDER BY created_at DESC LIMIT 1;

  IF inv IS NULL THEN
    INSERT INTO public.invoices(invoice_number,patient_id,total_amount,created_by)
    VALUES ('INV-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS') || '-' || substr(gen_random_uuid()::text,1,6), _patient_id, 0, auth.uid())
    RETURNING id INTO inv;
  END IF;

  SELECT amount INTO tariff FROM public.service_tariffs WHERE service_code='CONSULTATION' AND active;
  IF tariff IS NOT NULL THEN
    INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,source_key,service_code,department)
    SELECT inv, 'Consultation', 1, tariff, tariff, 'consultation', 'appointment', a.id,
           'appointment:'||a.id::text, 'CONSULTATION','consultation'
    FROM public.appointments a
    WHERE a.patient_id=_patient_id AND a.scheduled_at BETWEEN _from AND _to
      AND a.status NOT IN ('cancelled','no_show')
      AND NOT EXISTS (SELECT 1 FROM public.invoice_items i WHERE i.source_key='appointment:'||a.id::text)
      AND NOT EXISTS (SELECT 1 FROM public.service_orders so WHERE so.related_entity_id=a.id AND so.department='consultation' AND so.status<>'cancelled');
  END IF;

  SELECT amount INTO tariff FROM public.service_tariffs WHERE service_code='LAB-GENERIC' AND active;
  IF tariff IS NOT NULL THEN
    FOR r IN SELECT l.id,l.test_name FROM public.lab_orders l WHERE l.patient_id=_patient_id AND l.created_at BETWEEN _from AND _to AND l.status<>'cancelled' LOOP
      INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,source_key,service_code,department)
      SELECT inv, r.test_name, 1, tariff, tariff, 'lab','lab_order',r.id,'lab_order:'||r.id::text,'LAB-GENERIC','laboratory'
      WHERE NOT EXISTS (SELECT 1 FROM public.invoice_items i WHERE i.source_key='lab_order:'||r.id::text);
    END LOOP;
  END IF;

  SELECT amount INTO tariff FROM public.service_tariffs WHERE service_code='PROCEDURE-GENERIC' AND active;
  FOR r IN SELECT so.id,so.service_name,so.amount,so.department,so.service_code
           FROM public.service_orders so
           WHERE so.patient_id=_patient_id AND so.created_at BETWEEN _from AND _to AND so.status<>'cancelled' LOOP
    INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,source_key,service_code,department)
    SELECT inv,r.service_name,1,COALESCE(r.amount,tariff,0),COALESCE(r.amount,tariff,0),
           CASE WHEN r.department='pharmacy' THEN 'pharmacy' WHEN r.department='laboratory' THEN 'lab' WHEN r.department='imaging' THEN 'imaging' ELSE 'procedure' END,
           'service_order',r.id,'service_order:'||r.id::text,COALESCE(r.service_code,'PROCEDURE-GENERIC'),r.department
    WHERE NOT EXISTS (SELECT 1 FROM public.invoice_items i WHERE i.source_key='service_order:'||r.id::text);
  END LOOP;

  FOR r IN SELECT p.id,p.medication,p.dosage,p.computed_quantity FROM public.prescriptions p
           WHERE p.patient_id=_patient_id AND p.created_at BETWEEN _from AND _to AND p.status<>'cancelled' LOOP
    SELECT amount INTO tariff FROM public.service_tariffs WHERE service_code='PROCEDURE-GENERIC' AND active;
    IF tariff IS NULL THEN tariff := 0; END IF;
    INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,source_key,service_code,department)
    SELECT inv,'Medication: '||r.medication,COALESCE(NULLIF(r.computed_quantity,0),1),tariff,
           COALESCE(NULLIF(r.computed_quantity,0),1)*tariff,'pharmacy','prescription',r.id,'prescription:'||r.id::text,'PROCEDURE-GENERIC','pharmacy'
    WHERE NOT EXISTS (SELECT 1 FROM public.invoice_items i WHERE i.source_key='prescription:'||r.id::text);
  END LOOP;

  SELECT amount INTO tariff FROM public.service_tariffs WHERE service_code='WARD-ACCOM' AND active;
  IF tariff IS NOT NULL AND to_regclass('public.admissions') IS NOT NULL THEN
    FOR r IN SELECT a.id,a.admitted_at,a.discharged_at,a.ward FROM public.admissions a
             WHERE a.patient_id=_patient_id AND a.admitted_at <= _to AND COALESCE(a.discharged_at,_to) >= _from LOOP
      days_count := GREATEST(1, CEIL(EXTRACT(EPOCH FROM (LEAST(COALESCE(r.discharged_at,_to),_to)-GREATEST(r.admitted_at,_from)))/86400)::INTEGER);
      INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,source_key,service_code,department)
      SELECT inv,'Accommodation: '||COALESCE(r.ward,'Ward'),days_count,tariff,days_count*tariff,'ward','admission',r.id,'admission:'||r.id::text,'WARD-ACCOM','other'
      WHERE NOT EXISTS (SELECT 1 FROM public.invoice_items i WHERE i.source_key='admission:'||r.id::text);
    END LOOP;
  END IF;

  UPDATE public.invoices i SET total_amount=COALESCE((SELECT SUM(ii.amount) FROM public.invoice_items ii WHERE ii.invoice_id=i.id),0), updated_at=now() WHERE i.id=inv;

  RETURN QUERY
  SELECT ii.invoice_id,ii.id,ii.source_type,ii.source_id,ii.description,ii.category,ii.department,ii.quantity,ii.unit_price,ii.amount,
         COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),
         ii.amount-COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),
         so.id,so.status
  FROM public.invoice_items ii
  LEFT JOIN LATERAL (SELECT s.id,s.status FROM public.service_orders s WHERE s.invoice_item_id=ii.id ORDER BY s.created_at DESC LIMIT 1) so ON true
  WHERE ii.invoice_id=inv
    AND ii.amount-COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0) > 0
  ORDER BY ii.created_at;
END;
$$;

-- Item-level payment allocation is the billing gate. Each selected item gets a service order,
-- then the existing release_service_order RPC opens the affected department.
CREATE OR REPLACE FUNCTION public.pay_selected_invoice_items(
  _invoice_id UUID,
  _item_ids UUID[],
  _method TEXT,
  _reference TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  item RECORD;
  pay_id UUID;
  alloc NUMERIC;
  total NUMERIC := 0;
  order_id UUID;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Billing access denied'; END IF;
  IF _item_ids IS NULL OR cardinality(_item_ids)=0 THEN RAISE EXCEPTION 'Select at least one unpaid item'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.invoices WHERE id=_invoice_id) THEN RAISE EXCEPTION 'Invoice not found'; END IF;

  FOR item IN
    SELECT ii.*, GREATEST(ii.amount-COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),0) AS due
    FROM public.invoice_items ii WHERE ii.invoice_id=_invoice_id AND ii.id=ANY(_item_ids)
  LOOP
    IF item.due > 0 THEN total := total + item.due; END IF;
  END LOOP;
  IF total <= 0 THEN RAISE EXCEPTION 'Selected items are already paid'; END IF;

  INSERT INTO public.payments(invoice_id,patient_id,amount,method,reference,received_by,notes)
  SELECT _invoice_id,patient_id,total,_method,_reference,auth.uid(),'Item-level payment';
  SELECT id INTO pay_id FROM public.payments WHERE invoice_id=_invoice_id AND received_by=auth.uid() ORDER BY created_at DESC LIMIT 1;

  FOR item IN
    SELECT ii.*, GREATEST(ii.amount-COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),0) AS due
    FROM public.invoice_items ii WHERE ii.invoice_id=_invoice_id AND ii.id=ANY(_item_ids)
  LOOP
    IF item.due <= 0 THEN CONTINUE; END IF;
    alloc := item.due;
    INSERT INTO public.invoice_item_payments(invoice_item_id,payment_id,amount) VALUES(item.id,pay_id,alloc);
    UPDATE public.invoice_items SET paid_at=now(),paid_by=auth.uid() WHERE id=item.id;

    SELECT id INTO order_id FROM public.service_orders WHERE invoice_item_id=item.id AND status<>'cancelled' ORDER BY created_at DESC LIMIT 1;
    IF order_id IS NULL AND item.department IS NOT NULL THEN
      INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,invoice_id,invoice_item_id,status,requested_by,service_code)
      VALUES((SELECT patient_id FROM public.invoices WHERE id=_invoice_id),item.department,item.description,item.amount,item.source_id,_invoice_id,item.id,'pending_payment_approval',auth.uid(),item.service_code)
      RETURNING id INTO order_id;
    END IF;
    IF order_id IS NOT NULL THEN
      PERFORM public.release_service_order(order_id,'Item payment received');
    END IF;
  END LOOP;

  RETURN jsonb_build_object('invoice_id',_invoice_id,'payment_id',pay_id,'amount',total);
END;
$$;
REVOKE ALL ON FUNCTION public.prepare_patient_billable_items(UUID,TIMESTAMPTZ,TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pay_selected_invoice_items(UUID,UUID[],TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.prepare_patient_billable_items(UUID,TIMESTAMPTZ,TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pay_selected_invoice_items(UUID,UUID[],TEXT,TEXT) TO authenticated;

-- Compute medication quantities from frequency/duration so pharmacy does not rely on manual counting.
ALTER TABLE public.prescriptions ADD COLUMN IF NOT EXISTS computed_quantity INTEGER;
CREATE OR REPLACE FUNCTION public.compute_prescription_quantity(_frequency TEXT,_duration TEXT,_dosage TEXT)
RETURNS INTEGER LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE f INTEGER; d INTEGER; dose_units INTEGER := 1; t TEXT := lower(trim(coalesce(_frequency,''))); dur TEXT := lower(trim(coalesce(_duration,''))); dos TEXT := lower(trim(coalesce(_dosage,'')));
BEGIN
  f := CASE WHEN t ~ '(^|[^0-9])(once|qd)([^a-z]|$)' THEN 1 WHEN t ~ 'twice|bid|2 ?times|q12h' THEN 2 WHEN t ~ 'thrice|tid|3 ?times|q8h' THEN 3 WHEN t ~ 'four|qid|4 ?times|q6h' THEN 4 WHEN t ~ 'q4h|every 4' THEN 6 WHEN t ~ 'every 6' THEN 4 WHEN t ~ 'every 8' THEN 3 WHEN t ~ 'every 12' THEN 2 ELSE NULL END;
  IF f IS NULL THEN RETURN NULL; END IF;
  d := COALESCE((regexp_match(dur,'([0-9]+)\s*day'))[1]::INTEGER,(regexp_match(dur,'([0-9]+)\s*week'))[1]::INTEGER*7,(regexp_match(dur,'([0-9]+)\s*month'))[1]::INTEGER*30,regexp_replace(dur,'[^0-9]','','g')::INTEGER,NULL);
  IF d IS NULL OR d <= 0 THEN RETURN NULL; END IF;
  IF dos ~ '^[0-9]+(\.[0-9]+)?\s*(tablet|capsule|tab|cap)' THEN dose_units := GREATEST(1,split_part(regexp_replace(dos,'[^0-9.]','','g'),'.',1)::INTEGER); END IF;
  RETURN f*d*dose_units;
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END; $$;
CREATE OR REPLACE FUNCTION public.set_prescription_quantity() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN NEW.computed_quantity:=public.compute_prescription_quantity(NEW.frequency,NEW.duration,NEW.dosage); RETURN NEW; END; $$;
DROP TRIGGER IF EXISTS trg_prescription_quantity ON public.prescriptions;
CREATE TRIGGER trg_prescription_quantity BEFORE INSERT OR UPDATE OF frequency,duration,dosage ON public.prescriptions FOR EACH ROW EXECUTE FUNCTION public.set_prescription_quantity();
UPDATE public.prescriptions SET computed_quantity=public.compute_prescription_quantity(frequency,duration,dosage) WHERE computed_quantity IS NULL;

ALTER TABLE public.medication_administrations
  ADD COLUMN IF NOT EXISTS due_window_minutes INTEGER NOT NULL DEFAULT 30,
  ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS lock_reason TEXT,
  ADD COLUMN IF NOT EXISTS reopened_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reopened_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reopen_reason TEXT,
  ADD COLUMN IF NOT EXISTS last_reminder_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.lock_overdue_medication_slots()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE n INTEGER;
BEGIN
  UPDATE public.medication_administrations
  SET locked_at=COALESCE(locked_at,now()), lock_reason=COALESCE(lock_reason,'Administration window elapsed without documentation'), updated_at=now()
  WHERE status='scheduled' AND scheduled_at IS NOT NULL AND scheduled_at + make_interval(mins => due_window_minutes) < now() AND locked_at IS NULL;
  GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END; $$;

CREATE OR REPLACE FUNCTION public.transition_medication_administration(
  _record_id UUID,_status TEXT,_reason TEXT DEFAULT NULL,_notes TEXT DEFAULT NULL,_witnessed_by UUID DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r public.medication_administrations; overdue BOOLEAN;
BEGIN
  SELECT * INTO r FROM public.medication_administrations WHERE id=_record_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Medication administration record not found'; END IF;
  overdue := r.scheduled_at IS NOT NULL AND now() > r.scheduled_at + make_interval(mins => r.due_window_minutes);
  IF _status='administered' AND r.locked_at IS NOT NULL THEN RAISE EXCEPTION 'Medication slot is locked. An authorised reopening with explanation is required.'; END IF;
  IF _status IN ('held','refused','omitted') AND r.locked_at IS NULL AND overdue THEN
    UPDATE public.medication_administrations SET locked_at=now(),lock_reason=COALESCE(_reason,'Late medication event requires explanation'),updated_at=now() WHERE id=_record_id;
    RAISE EXCEPTION 'Medication slot has elapsed. Reopen it with an authorised explanation before documenting the event.';
  END IF;
  IF _status='administered' THEN
    UPDATE public.medication_administrations SET status='administered',administered_at=now(),administered_by=auth.uid(),witnessed_by=COALESCE(_witnessed_by,witnessed_by),reason=_reason,notes=COALESCE(_notes,notes),updated_at=now() WHERE id=_record_id;
  ELSE
    UPDATE public.medication_administrations SET status=_status,reason=_reason,notes=COALESCE(_notes,notes),updated_at=now() WHERE id=_record_id;
  END IF;
  PERFORM public.record_system_audit('medication_administration_'||_status,'clinical','medication_administrations',_record_id,CASE WHEN _status='administered' THEN 'info' ELSE 'warning' END,jsonb_build_object('record_id',_record_id,'administered_by',auth.uid(),'timestamp',now(),'reason',_reason,'witnessed_by',_witnessed_by));
  RETURN jsonb_build_object('id',_record_id,'status',_status,'administered_by',auth.uid(),'administered_at',now());
END; $$;

CREATE OR REPLACE FUNCTION public.reopen_medication_administration(_record_id UUID,_reason TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Authorised clinical role required'; END IF;
  IF trim(coalesce(_reason,''))='' THEN RAISE EXCEPTION 'A reopening explanation is required'; END IF;
  UPDATE public.medication_administrations SET locked_at=NULL,lock_reason=NULL,reopened_at=now(),reopened_by=auth.uid(),reopen_reason=_reason,updated_at=now() WHERE id=_record_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Medication administration record not found'; END IF;
  PERFORM public.record_system_audit('medication_administration_reopened','clinical','medication_administrations',_record_id,'warning',jsonb_build_object('record_id',_record_id,'reopened_by',auth.uid(),'timestamp',now(),'reason',_reason));
  RETURN jsonb_build_object('id',_record_id,'reopened_by',auth.uid(),'reopened_at',now());
END; $$;
REVOKE ALL ON FUNCTION public.lock_overdue_medication_slots() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reopen_medication_administration(UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lock_overdue_medication_slots() TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reopen_medication_administration(UUID,TEXT) TO authenticated;
