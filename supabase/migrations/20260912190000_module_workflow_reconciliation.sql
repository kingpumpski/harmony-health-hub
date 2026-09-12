-- Module workflow reconciliation.
-- Keeps the existing billing/service-order architecture and hardens the operational edges:
-- billing retains paid history, invoices close correctly, pharmacy inventory writes are controlled,
-- and medication administration is attributed, locked, reopenable and shift-aware.

-- -----------------------------------------------------------------------------
-- BILLING: keep paid history visible and close invoice state consistently.
-- -----------------------------------------------------------------------------
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
    SELECT inv,'Consultation',1,tariff,tariff,'consultation','appointment',a.id,'appointment:'||a.id::text,'CONSULTATION','consultation'
    FROM public.appointments a
    WHERE a.patient_id=_patient_id AND a.scheduled_at BETWEEN _from AND _to
      AND a.status NOT IN ('cancelled','no_show')
      AND NOT EXISTS (SELECT 1 FROM public.invoice_items i WHERE i.source_key='appointment:'||a.id::text);
  END IF;

  SELECT amount INTO tariff FROM public.service_tariffs WHERE service_code='LAB-GENERIC' AND active;
  IF tariff IS NOT NULL THEN
    FOR r IN SELECT l.id,l.test_name FROM public.lab_orders l
             WHERE l.patient_id=_patient_id AND l.created_at BETWEEN _from AND _to AND l.status<>'cancelled' LOOP
      INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,source_key,service_code,department)
      SELECT inv,r.test_name,1,tariff,tariff,'lab','lab_order',r.id,'lab_order:'||r.id::text,'LAB-GENERIC','laboratory'
      WHERE NOT EXISTS (SELECT 1 FROM public.invoice_items i WHERE i.source_key='lab_order:'||r.id::text);
    END LOOP;
  END IF;

  SELECT amount INTO tariff FROM public.service_tariffs WHERE service_code='PROCEDURE-GENERIC' AND active;
  FOR r IN SELECT so.id,so.service_name,so.amount,so.department,so.service_code
           FROM public.service_orders so
           WHERE so.patient_id=_patient_id AND so.created_at BETWEEN _from AND _to AND so.status<>'cancelled' LOOP
    INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,source_key,service_code,department)
    SELECT inv,r.service_name,1,COALESCE(r.amount,tariff,0),COALESCE(r.amount,tariff,0),
      CASE WHEN r.department='pharmacy' THEN 'pharmacy' WHEN r.department='laboratory' THEN 'lab' WHEN r.department IN ('imaging','radiology') THEN 'imaging' ELSE 'procedure' END,
      'service_order',r.id,'service_order:'||r.id::text,COALESCE(r.service_code,'PROCEDURE-GENERIC'),r.department
    WHERE NOT EXISTS (SELECT 1 FROM public.invoice_items i WHERE i.source_key='service_order:'||r.id::text);
  END LOOP;

  FOR r IN SELECT p.id,p.medication,p.dosage,p.computed_quantity FROM public.prescriptions p
           WHERE p.patient_id=_patient_id AND p.created_at BETWEEN _from AND _to AND p.status<>'cancelled' LOOP
    INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,source_key,service_code,department)
    SELECT inv,'Medication: '||r.medication,GREATEST(COALESCE(NULLIF(r.computed_quantity,0),1),1),tariff,
      GREATEST(COALESCE(NULLIF(r.computed_quantity,0),1),1)*tariff,'pharmacy','prescription',r.id,'prescription:'||r.id::text,'PROCEDURE-GENERIC','pharmacy'
    WHERE tariff IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.invoice_items i WHERE i.source_key='prescription:'||r.id::text);
  END LOOP;

  SELECT amount INTO tariff FROM public.service_tariffs WHERE service_code='WARD-ACCOM' AND active;
  IF tariff IS NOT NULL AND to_regclass('public.admissions') IS NOT NULL THEN
    FOR r IN SELECT a.id,a.admitted_at,a.discharged_at,a.ward FROM public.admissions a
             WHERE a.patient_id=_patient_id AND a.admitted_at <= _to AND COALESCE(a.discharged_at,_to) >= _from LOOP
      days_count := GREATEST(1, CEIL(EXTRACT(EPOCH FROM (LEAST(COALESCE(r.discharged_at,_to),_to)-GREATEST(r.admitted_at,_from)))/86400)::INTEGER);
      INSERT INTO public.invoice_items(invoice_id,description,quantity,unit_price,amount,category,source_type,source_id,source_key,service_code,department)
      SELECT inv,'Accommodation: '||COALESCE(r.ward,'Ward'),days_count,tariff,days_count*tariff,'ward','admission',r.id,'admission:'||r.id::text,'WARD-ACCOM','ward'
      WHERE NOT EXISTS (SELECT 1 FROM public.invoice_items i WHERE i.source_key='admission:'||r.id::text);
    END LOOP;
  END IF;

  UPDATE public.invoices i
  SET total_amount=COALESCE((SELECT SUM(ii.amount) FROM public.invoice_items ii WHERE ii.invoice_id=i.id),0), updated_at=now()
  WHERE i.id=inv;

  RETURN QUERY
  SELECT ii.invoice_id,ii.id,ii.source_type,ii.source_id,ii.description,ii.category,ii.department,ii.quantity,ii.unit_price,ii.amount,
    COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),
    GREATEST(ii.amount-COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),0),
    so.id,so.status
  FROM public.invoice_items ii
  LEFT JOIN LATERAL (SELECT s.id,s.status FROM public.service_orders s WHERE s.invoice_item_id=ii.id ORDER BY s.created_at DESC LIMIT 1) so ON true
  WHERE ii.invoice_id=inv
  ORDER BY ii.created_at;
END;
$$;

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
  patient UUID;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'accountant') OR public.has_role(auth.uid(),'front_desk')) THEN RAISE EXCEPTION 'Billing access denied'; END IF;
  IF _item_ids IS NULL OR cardinality(_item_ids)=0 THEN RAISE EXCEPTION 'Select at least one unpaid item'; END IF;
  SELECT patient_id INTO patient FROM public.invoices WHERE id=_invoice_id FOR UPDATE;
  IF patient IS NULL THEN RAISE EXCEPTION 'Invoice not found'; END IF;

  FOR item IN SELECT ii.*,GREATEST(ii.amount-COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),0) AS due
              FROM public.invoice_items ii WHERE ii.invoice_id=_invoice_id AND ii.id=ANY(_item_ids) FOR UPDATE LOOP
    IF item.due > 0 THEN total := total + item.due; END IF;
  END LOOP;
  IF total <= 0 THEN RAISE EXCEPTION 'Selected items are already paid'; END IF;

  INSERT INTO public.payments(invoice_id,patient_id,amount,method,reference,received_by,notes)
  VALUES(_invoice_id,patient,total,_method,_reference,auth.uid(),'Item-level payment')
  RETURNING id INTO pay_id;

  FOR item IN SELECT ii.*,GREATEST(ii.amount-COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0),0) AS due
              FROM public.invoice_items ii WHERE ii.invoice_id=_invoice_id AND ii.id=ANY(_item_ids) FOR UPDATE LOOP
    IF item.due <= 0 THEN CONTINUE; END IF;
    alloc := item.due;
    INSERT INTO public.invoice_item_payments(invoice_item_id,payment_id,amount) VALUES(item.id,pay_id,alloc);
    UPDATE public.invoice_items SET paid_at=now(),paid_by=auth.uid() WHERE id=item.id;
    SELECT id INTO order_id FROM public.service_orders WHERE invoice_item_id=item.id AND status<>'cancelled' ORDER BY created_at DESC LIMIT 1;
    IF order_id IS NULL AND item.department IS NOT NULL THEN
      INSERT INTO public.service_orders(patient_id,department,service_name,amount,related_entity_id,invoice_id,invoice_item_id,status,requested_by,service_code,created_by)
      VALUES(patient,item.department,item.description,item.amount,item.source_id,_invoice_id,item.id,'pending_payment_approval',auth.uid(),item.service_code,auth.uid())
      RETURNING id INTO order_id;
    END IF;
    IF order_id IS NOT NULL THEN PERFORM public.release_service_order(order_id,'Payment received for selected billing item'); END IF;
  END LOOP;

  UPDATE public.invoices i
  SET status=CASE WHEN COALESCE((SELECT SUM(ii.amount) FROM public.invoice_items ii WHERE ii.invoice_id=i.id),0)
                       <= COALESCE((SELECT SUM(ip.amount) FROM public.invoice_item_payments ip JOIN public.invoice_items ii ON ii.id=ip.invoice_item_id WHERE ii.invoice_id=i.id),0)
                  THEN 'paid' ELSE 'partially_paid' END,
      updated_at=now()
  WHERE i.id=_invoice_id;

  RETURN jsonb_build_object('invoice_id',_invoice_id,'payment_id',pay_id,'amount',total);
END;
$$;

-- -----------------------------------------------------------------------------
-- PHARMACY: inventory changes are pharmacist/admin controlled through an RPC.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_pharmacy_inventory_item(
  _drug_name TEXT,
  _strength TEXT,
  _stock_quantity INTEGER,
  _reorder_level INTEGER,
  _unit_price NUMERIC
)
RETURNS public.pharmacy_inventory
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE r public.pharmacy_inventory;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
  IF length(trim(COALESCE(_drug_name,''))) < 2 THEN RAISE EXCEPTION 'Drug name is required'; END IF;
  IF COALESCE(_stock_quantity,0) < 0 OR COALESCE(_reorder_level,0) < 0 OR COALESCE(_unit_price,0) < 0 THEN RAISE EXCEPTION 'Inventory values cannot be negative'; END IF;
  INSERT INTO public.pharmacy_inventory(drug_name,strength,stock_quantity,reorder_level,unit_price)
  VALUES(trim(_drug_name),NULLIF(trim(COALESCE(_strength,'')),''),COALESCE(_stock_quantity,0),COALESCE(_reorder_level,0),COALESCE(_unit_price,0))
  RETURNING * INTO r;
  PERFORM public.record_system_audit('pharmacy_inventory_created','pharmacy','pharmacy_inventory',r.id,'info',jsonb_build_object('drug_name',r.drug_name,'stock_quantity',r.stock_quantity,'actor_id',auth.uid()));
  RETURN r;
END;
$$;
REVOKE ALL ON FUNCTION public.create_pharmacy_inventory_item(TEXT,TEXT,INTEGER,INTEGER,NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_inventory_item(TEXT,TEXT,INTEGER,INTEGER,NUMERIC) TO authenticated;

-- -----------------------------------------------------------------------------
-- MEDICATION ADMINISTRATION: shift-aware reminders and secure scheduling.
-- -----------------------------------------------------------------------------
ALTER TABLE public.medication_administrations
  ADD COLUMN IF NOT EXISTS due_window_minutes INTEGER NOT NULL DEFAULT 30 CHECK (due_window_minutes BETWEEN 5 AND 240),
  ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS lock_reason TEXT,
  ADD COLUMN IF NOT EXISTS reopened_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reopen_reason TEXT;

CREATE TABLE IF NOT EXISTS public.staff_shift_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  department TEXT NOT NULL,
  shift_label TEXT NOT NULL,
  starts_at TIMESTAMPTZ NOT NULL,
  ends_at TIMESTAMPTZ NOT NULL,
  active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);
CREATE INDEX IF NOT EXISTS idx_staff_shift_on_duty ON public.staff_shift_assignments(department,starts_at,ends_at) WHERE active;
ALTER TABLE public.staff_shift_assignments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff read own shift assignments" ON public.staff_shift_assignments;
CREATE POLICY "staff read own shift assignments" ON public.staff_shift_assignments FOR SELECT TO authenticated
USING (user_id=auth.uid() OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS "admin manage shift assignments" ON public.staff_shift_assignments;
CREATE POLICY "admin manage shift assignments" ON public.staff_shift_assignments FOR ALL TO authenticated
USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

CREATE TABLE IF NOT EXISTS public.medication_due_notification_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  medication_administration_id UUID NOT NULL REFERENCES public.medication_administrations(id) ON DELETE CASCADE,
  recipient_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reminder_bucket TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(medication_administration_id,recipient_user_id,reminder_bucket)
);
ALTER TABLE public.medication_due_notification_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "medication reminder log admin read" ON public.medication_due_notification_log;
CREATE POLICY "medication reminder log admin read" ON public.medication_due_notification_log FOR SELECT TO authenticated USING (public.has_role(auth.uid(),'admin') OR recipient_user_id=auth.uid());

CREATE OR REPLACE FUNCTION public.schedule_medication_administration(
  _patient_id UUID,
  _medication_name TEXT,
  _dose TEXT DEFAULT NULL,
  _route TEXT DEFAULT NULL,
  _scheduled_at TIMESTAMPTZ DEFAULT NULL,
  _notes TEXT DEFAULT NULL,
  _due_window_minutes INTEGER DEFAULT 30
)
RETURNS public.medication_administrations
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE r public.medication_administrations;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN RAISE EXCEPTION 'Patient not found'; END IF;
  IF length(trim(COALESCE(_medication_name,''))) < 2 THEN RAISE EXCEPTION 'Medication name is required'; END IF;
  INSERT INTO public.medication_administrations(patient_id,medication_name,dose,route,scheduled_at,notes,due_window_minutes)
  VALUES(_patient_id,trim(_medication_name),NULLIF(trim(COALESCE(_dose,'')),''),NULLIF(trim(COALESCE(_route,'')),''),_scheduled_at,_notes,LEAST(GREATEST(COALESCE(_due_window_minutes,30),5),240))
  RETURNING * INTO r;
  PERFORM public.record_system_audit('medication_scheduled','clinical','medication_administrations',r.id,'info',jsonb_build_object('patient_id',r.patient_id,'scheduled_at',r.scheduled_at,'actor_id',auth.uid()));
  RETURN r;
END;
$$;

CREATE OR REPLACE FUNCTION public.lock_overdue_medication_slots()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE n INTEGER;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  UPDATE public.medication_administrations
  SET locked_at=now(),lock_reason='Administration window elapsed without a documented outcome',updated_at=now()
  WHERE status='scheduled' AND scheduled_at IS NOT NULL AND locked_at IS NULL
    AND now() > scheduled_at + make_interval(mins => due_window_minutes);
  GET DIAGNOSTICS n=ROW_COUNT;
  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION public.transition_medication_administration(
  _record_id UUID,
  _status TEXT,
  _reason TEXT DEFAULT NULL,
  _notes TEXT DEFAULT NULL,
  _witnessed_by UUID DEFAULT NULL
)
RETURNS public.medication_administrations
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE r public.medication_administrations;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
  IF _status NOT IN ('administered','held','refused','omitted','cancelled') THEN RAISE EXCEPTION 'Invalid medication status'; END IF;
  SELECT * INTO r FROM public.medication_administrations WHERE id=_record_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Medication administration record not found'; END IF;
  IF r.locked_at IS NOT NULL THEN RAISE EXCEPTION 'Medication slot is locked; provide an authorised reopening explanation first'; END IF;
  IF r.status <> 'scheduled' THEN RAISE EXCEPTION 'Medication slot has already been documented'; END IF;
  UPDATE public.medication_administrations
  SET status=_status,reason=NULLIF(trim(COALESCE(_reason,'')),''),notes=COALESCE(_notes,notes),
      administered_by=CASE WHEN _status='administered' THEN auth.uid() ELSE administered_by END,
      administered_at=CASE WHEN _status='administered' THEN now() ELSE administered_at END,
      witnessed_by=CASE WHEN _status='administered' THEN _witnessed_by ELSE witnessed_by END,
      updated_at=now()
  WHERE id=_record_id RETURNING * INTO r;
  PERFORM public.record_system_audit('medication_'||_status,'clinical','medication_administrations',r.id,'info',jsonb_build_object('patient_id',r.patient_id,'status',r.status,'administered_by',r.administered_by,'administered_at',r.administered_at,'reason',r.reason));
  RETURN r;
END;
$$;

CREATE OR REPLACE FUNCTION public.reopen_medication_administration(_record_id UUID,_reason TEXT)
RETURNS public.medication_administrations
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE r public.medication_administrations;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'practitioner')) THEN RAISE EXCEPTION 'Clinical role required'; END IF;
  IF length(trim(COALESCE(_reason,''))) < 5 THEN RAISE EXCEPTION 'A professional reopening explanation is required'; END IF;
  UPDATE public.medication_administrations
  SET locked_at=NULL,lock_reason=NULL,reopened_at=now(),reopen_reason=trim(_reason),updated_at=now()
  WHERE id=_record_id AND locked_at IS NOT NULL
  RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Locked medication slot not found'; END IF;
  PERFORM public.record_system_audit('medication_slot_reopened','clinical','medication_administrations',r.id,'warning',jsonb_build_object('patient_id',r.patient_id,'reason',_reason,'actor_id',auth.uid()));
  RETURN r;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_due_medications()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $$
DECLARE r RECORD; n INTEGER:=0; bucket TEXT;
BEGIN
  IF NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse')) THEN RAISE EXCEPTION 'Nursing role required'; END IF;
  FOR r IN
    SELECT m.*,p.first_name,p.last_name
    FROM public.medication_administrations m
    JOIN public.patients p ON p.id=m.patient_id
    WHERE m.status='scheduled' AND m.scheduled_at IS NOT NULL AND m.locked_at IS NULL
      AND m.scheduled_at <= now() + interval '15 minutes'
      AND m.scheduled_at >= now() - make_interval(mins => m.due_window_minutes)
  LOOP
    bucket := CASE WHEN r.scheduled_at > now() THEN 'upcoming_15m' ELSE 'overdue_window' END;
    INSERT INTO public.medication_due_notification_log(medication_administration_id,recipient_user_id,reminder_bucket)
    SELECT r.id,s.user_id,bucket
    FROM public.staff_shift_assignments s
    JOIN public.profiles pr ON pr.id=s.user_id
    WHERE s.active AND lower(s.department) IN ('nursing','nurse','midwifery','midwife')
      AND s.starts_at <= now() AND s.ends_at >= now()
      AND NOT EXISTS(SELECT 1 FROM public.medication_due_notification_log l WHERE l.medication_administration_id=r.id AND l.recipient_user_id=s.user_id AND l.reminder_bucket=bucket)
    ON CONFLICT DO NOTHING;
    INSERT INTO public.notifications(recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata)
    SELECT s.user_id,'Medication due',r.medication_name||' for '||r.first_name||' '||r.last_name||' is due now or within 15 minutes.', 'warning','prescription','/medications',r.patient_id,r.id,jsonb_build_object('scheduled_at',r.scheduled_at,'reminder_bucket',bucket)
    FROM public.staff_shift_assignments s
    WHERE s.active AND lower(s.department) IN ('nursing','nurse','midwifery','midwife') AND s.starts_at <= now() AND s.ends_at >= now()
      AND EXISTS(SELECT 1 FROM public.medication_due_notification_log l WHERE l.medication_administration_id=r.id AND l.recipient_user_id=s.user_id AND l.reminder_bucket=bucket)
      AND NOT EXISTS(SELECT 1 FROM public.notifications n WHERE n.recipient_user_id=s.user_id AND n.related_entity_id=r.id AND n.metadata->>'reminder_bucket'=bucket);
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

REVOKE ALL ON FUNCTION public.schedule_medication_administration(UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.lock_overdue_medication_slots() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reopen_medication_administration(UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_due_medications() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schedule_medication_administration(UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.lock_overdue_medication_slots() TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_medication_administration(UUID,TEXT,TEXT,TEXT,UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reopen_medication_administration(UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_due_medications() TO authenticated;
