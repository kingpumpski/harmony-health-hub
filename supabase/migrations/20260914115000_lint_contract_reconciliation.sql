ALTER TABLE public.department_queues ADD COLUMN IF NOT EXISTS service_order_id uuid REFERENCES public.service_orders(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_department_queues_service_order_id ON public.department_queues(service_order_id);
ALTER TABLE public.billing_overrides ADD COLUMN IF NOT EXISTS service_order_id uuid REFERENCES public.service_orders(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_billing_overrides_service_order_id ON public.billing_overrides(service_order_id);
ALTER TABLE public.pharmacy_inventory ADD COLUMN IF NOT EXISTS batch_number text;
ALTER TABLE public.pharmacy_dispensing_plans ADD COLUMN IF NOT EXISTS computed_quantity integer;

CREATE OR REPLACE FUNCTION public.start_imaging_order(_imaging_order_id uuid)
RETURNS public.imaging_orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.imaging_orders%ROWTYPE;
BEGIN
 UPDATE public.imaging_orders SET status='in_progress', started_at=COALESCE(started_at,now()), updated_at=now() WHERE id=_imaging_order_id RETURNING * INTO v;
 IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;
 UPDATE public.department_queues SET status='claimed', claimed_by=auth.uid(), assigned_to=auth.uid(), claimed_at=COALESCE(claimed_at,now()), updated_at=now() WHERE service_order_id=v.service_order_id;
 RETURN v;
END; $$;

CREATE OR REPLACE FUNCTION public.complete_imaging_order(_imaging_order_id uuid,_report text,_impression text)
RETURNS public.imaging_orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.imaging_orders%ROWTYPE;
BEGIN
 UPDATE public.imaging_orders SET status='completed', report=_report, impression=_impression, completed_at=COALESCE(completed_at,now()), updated_at=now() WHERE id=_imaging_order_id RETURNING * INTO v;
 IF NOT FOUND THEN RAISE EXCEPTION 'Imaging order not found'; END IF;
 UPDATE public.department_queues SET status='completed', completed_at=now(), updated_at=now() WHERE service_order_id=v.service_order_id;
 RETURN v;
END; $$;

CREATE OR REPLACE FUNCTION public.release_service_order(_service_order_id uuid,_reason text DEFAULT 'Payment received')
RETURNS public.service_orders
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v public.service_orders%ROWTYPE;
BEGIN
 SELECT * INTO v FROM public.service_orders WHERE id=_service_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Service order not found'; END IF;
 UPDATE public.service_orders SET status='released', updated_at=now() WHERE id=v.id RETURNING * INTO v;
 RETURN v;
END; $$;

CREATE OR REPLACE FUNCTION public.prepare_pharmacy_dispensing(_prescription_id uuid,_inventory_id uuid,_quantity integer,_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE p public.prescriptions%ROWTYPE; i public.pharmacy_inventory%ROWTYPE; v_id uuid;
BEGIN
 SELECT * INTO p FROM public.prescriptions WHERE id=_prescription_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Prescription not found'; END IF;
 SELECT * INTO i FROM public.pharmacy_inventory WHERE id=_inventory_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Inventory item not found'; END IF;
 INSERT INTO public.pharmacy_dispensing_plans(prescription_id,patient_id,inventory_id,medication_name,prescribed_dose,prescribed_frequency,prescribed_duration,computed_quantity,prepared_quantity,prepared_by,notes)
 VALUES(p.id,p.patient_id,i.id,i.drug_name,p.dosage,p.frequency,p.duration,COALESCE(_quantity,0),COALESCE(_quantity,0),auth.uid(),_notes) RETURNING id INTO v_id;
 RETURN jsonb_build_object('id',v_id,'prescription_id',p.id,'inventory_id',i.id,'quantity',COALESCE(_quantity,0),'status','prepared');
END; $$;

NOTIFY pgrst,'reload schema';