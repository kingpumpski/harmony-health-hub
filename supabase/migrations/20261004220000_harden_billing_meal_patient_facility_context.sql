-- Harden billing/meal patient writes with facility lineage and empty search paths.
-- No data is reassigned by this migration.

CREATE OR REPLACE FUNCTION public.mark_meal_order_delivered(_order_id uuid)
RETURNS public.meal_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_order public.meal_orders;
  v_patient_facility uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
    OR public.has_role(uid,'canteen')
  ) THEN
    RAISE EXCEPTION 'Meal delivery update is not permitted';
  END IF;

  SELECT * INTO v_order
  FROM public.meal_orders
  WHERE id = _order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Meal order not found';
  END IF;

  v_patient_facility := public.assert_patient_facility_context(v_order.patient_id);

  IF v_order.facility_id IS NULL THEN
    RAISE EXCEPTION 'Meal order facility attribution is unresolved';
  END IF;

  IF v_order.facility_id IS DISTINCT FROM v_patient_facility THEN
    RAISE EXCEPTION 'Meal order and patient facility context do not match';
  END IF;

  IF v_order.status = 'delivered' THEN
    RETURN v_order;
  END IF;

  UPDATE public.meal_orders
  SET status = 'delivered',
      delivered_at = COALESCE(delivered_at, pg_catalog.now())
  WHERE id = _order_id
  RETURNING * INTO v_order;

  PERFORM public.record_system_audit(
    'meal_order_delivered',
    'canteen',
    'meal_order',
    v_order.id,
    'info',
    pg_catalog.jsonb_build_object(
      'patient_id', v_order.patient_id,
      'actor_user_id', uid,
      'facility_id', v_patient_facility
    )
  );

  RETURN v_order;
END;
$function$;

CREATE OR REPLACE FUNCTION public.record_patient_deposit(
  _patient_id uuid,
  _amount numeric,
  _reference text DEFAULT NULL::text
)
RETURNS public.patient_account_credits
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v public.patient_account_credits;
  v_patient_facility uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'it_admin')
    OR public.has_role(auth.uid(),'accountant')
    OR public.has_role(auth.uid(),'front_desk')
  ) THEN
    RAISE EXCEPTION 'Billing access denied';
  END IF;

  IF _amount IS NULL OR _amount <= 0 THEN
    RAISE EXCEPTION 'Deposit amount must be positive';
  END IF;

  v_patient_facility := public.assert_patient_facility_context(_patient_id);

  INSERT INTO public.patient_account_credits(
    patient_id,
    entry_type,
    amount,
    reference,
    created_by,
    facility_id
  )
  VALUES (
    _patient_id,
    'deposit',
    pg_catalog.round(_amount,2),
    NULLIF(pg_catalog.btrim(_reference),''),
    auth.uid(),
    v_patient_facility
  )
  RETURNING * INTO v;

  RETURN v;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prepare_patient_billable_items(
  _patient_id uuid,
  _from timestamp with time zone DEFAULT date_trunc('day'::text, now()),
  _to timestamp with time zone DEFAULT now()
)
RETURNS TABLE(
  invoice_id uuid,
  invoice_item_id uuid,
  source_type text,
  source_id uuid,
  description text,
  category text,
  department text,
  quantity integer,
  unit_price numeric,
  amount numeric,
  paid_amount numeric,
  outstanding_amount numeric,
  service_order_id uuid,
  service_order_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  inv uuid;
  tariff numeric;
  r record;
  days_count integer;
  uid uuid := auth.uid();
  v_patient_facility uuid;
  v_invoice_facility uuid;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'accountant')
    OR public.has_role(uid,'front_desk')
  ) THEN
    RAISE EXCEPTION 'Billing access denied';
  END IF;

  IF _patient_id IS NULL OR _from IS NULL OR _to IS NULL OR _from > _to THEN
    RAISE EXCEPTION 'Invalid patient billing period';
  END IF;

  v_patient_facility := public.assert_patient_facility_context(_patient_id);

  PERFORM pg_advisory_xact_lock(pg_catalog.hashtextextended(_patient_id::text,0));

  SELECT id, facility_id
  INTO inv, v_invoice_facility
  FROM public.invoices
  WHERE patient_id = _patient_id
    AND status IN ('pending','partially_paid')
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF inv IS NOT NULL THEN
    IF v_invoice_facility IS NULL THEN
      RAISE EXCEPTION 'Invoice facility attribution is unresolved';
    END IF;
    IF v_invoice_facility IS DISTINCT FROM v_patient_facility THEN
      RAISE EXCEPTION 'Invoice and patient facility context do not match';
    END IF;
  ELSE
    INSERT INTO public.invoices(
      invoice_number,
      patient_id,
      total_amount,
      created_by,
      facility_id
    )
    VALUES(
      'INV-' || pg_catalog.to_char(pg_catalog.clock_timestamp(),'YYYYMMDDHH24MISSMS') || '-' ||
        pg_catalog.substr(gen_random_uuid()::text,1,6),
      _patient_id,
      0,
      uid,
      v_patient_facility
    )
    RETURNING id INTO inv;
  END IF;

  SELECT st.amount INTO tariff
  FROM public.service_tariffs st
  WHERE st.service_code = 'CONSULTATION'
    AND st.active
    AND st.effective_from <= _to::date
    AND (st.effective_to IS NULL OR st.effective_to >= _from::date)
  ORDER BY st.effective_from DESC NULLS LAST
  LIMIT 1;

  IF tariff IS NOT NULL THEN
    INSERT INTO public.invoice_items(
      invoice_id,description,quantity,unit_price,amount,category,
      source_type,source_id,service_code,department
    )
    SELECT
      inv,'Consultation',1,tariff,tariff,'consultation',
      'appointment',a.id,'CONSULTATION','consultation'
    FROM public.appointments a
    WHERE a.patient_id = _patient_id
      AND a.scheduled_at BETWEEN _from AND _to
      AND a.status NOT IN ('cancelled','no_show')
      AND NOT EXISTS(
        SELECT 1 FROM public.invoice_items i
        WHERE i.source_type='appointment' AND i.source_id=a.id
      )
      AND NOT EXISTS(
        SELECT 1 FROM public.service_orders so
        WHERE so.patient_id=a.patient_id
          AND so.related_entity_id=a.id
          AND so.department='consultation'
          AND so.status<>'cancelled'
      );
  END IF;

  SELECT st.amount INTO tariff
  FROM public.service_tariffs st
  WHERE st.service_code='LAB-GENERIC'
    AND st.active
    AND st.effective_from<=_to::date
    AND (st.effective_to IS NULL OR st.effective_to>=_from::date)
  ORDER BY st.effective_from DESC NULLS LAST
  LIMIT 1;

  IF tariff IS NOT NULL THEN
    FOR r IN
      SELECT l.id,l.test_name
      FROM public.lab_orders l
      WHERE l.patient_id=_patient_id
        AND l.created_at BETWEEN _from AND _to
        AND l.status<>'cancelled'
        AND NOT EXISTS(
          SELECT 1 FROM public.service_orders so
          WHERE so.patient_id=l.patient_id
            AND so.related_entity_id=l.id
            AND so.department='laboratory'
            AND so.status<>'cancelled'
        )
    LOOP
      INSERT INTO public.invoice_items(
        invoice_id,description,quantity,unit_price,amount,category,
        source_type,source_id,service_code,department
      )
      SELECT inv,r.test_name,1,tariff,tariff,'lab',
        'lab_order',r.id,'LAB-GENERIC','laboratory'
      WHERE NOT EXISTS(
        SELECT 1 FROM public.invoice_items i
        WHERE i.source_type='lab_order' AND i.source_id=r.id
      );
    END LOOP;
  END IF;

  SELECT st.amount INTO tariff
  FROM public.service_tariffs st
  WHERE st.service_code='PROCEDURE-GENERIC'
    AND st.active
    AND st.effective_from<=_to::date
    AND (st.effective_to IS NULL OR st.effective_to>=_from::date)
  ORDER BY st.effective_from DESC NULLS LAST
  LIMIT 1;

  FOR r IN
    SELECT so.id,so.service_name,so.amount,so.department,so.service_code,so.quantity
    FROM public.service_orders so
    WHERE so.patient_id=_patient_id
      AND so.created_at BETWEEN _from AND _to
      AND so.status<>'cancelled'
  LOOP
    INSERT INTO public.invoice_items(
      invoice_id,description,quantity,unit_price,amount,category,
      source_type,source_id,service_code,department
    )
    SELECT
      inv,r.service_name,pg_catalog.greatest(pg_catalog.coalesce(r.quantity,1),1),
      pg_catalog.coalesce(NULLIF(r.amount,0),tariff,0),
      pg_catalog.coalesce(NULLIF(r.amount,0),tariff,0) *
        pg_catalog.greatest(pg_catalog.coalesce(r.quantity,1),1),
      CASE
        WHEN r.department='pharmacy' THEN 'pharmacy'
        WHEN r.department='laboratory' THEN 'lab'
        WHEN r.department IN('imaging','radiology') THEN 'imaging'
        ELSE 'procedure'
      END,
      'service_order',r.id,pg_catalog.coalesce(r.service_code,'PROCEDURE-GENERIC'),r.department
    WHERE NOT EXISTS(
      SELECT 1 FROM public.invoice_items i
      WHERE i.source_type='service_order' AND i.source_id=r.id
    );
  END LOOP;

  SELECT st.amount INTO tariff
  FROM public.service_tariffs st
  WHERE st.service_code='PROCEDURE-GENERIC'
    AND st.active
    AND st.effective_from<=_to::date
    AND (st.effective_to IS NULL OR st.effective_to>=_from::date)
  ORDER BY st.effective_from DESC NULLS LAST
  LIMIT 1;

  IF tariff IS NOT NULL THEN
    FOR r IN
      SELECT p.id,p.medication,p.computed_quantity
      FROM public.prescriptions p
      WHERE p.patient_id=_patient_id
        AND p.created_at BETWEEN _from AND _to
        AND p.status<>'cancelled'
        AND NOT EXISTS(
          SELECT 1 FROM public.service_orders so
          WHERE so.patient_id=p.patient_id
            AND so.related_entity_id=p.id
            AND so.department='pharmacy'
            AND so.status<>'cancelled'
        )
    LOOP
      INSERT INTO public.invoice_items(
        invoice_id,description,quantity,unit_price,amount,category,
        source_type,source_id,service_code,department
      )
      SELECT
        inv,
        'Medication: '||r.medication,
        pg_catalog.greatest(pg_catalog.coalesce(NULLIF(r.computed_quantity,0),1),1),
        tariff,
        pg_catalog.greatest(pg_catalog.coalesce(NULLIF(r.computed_quantity,0),1),1)*tariff,
        'pharmacy','prescription',r.id,'PROCEDURE-GENERIC','pharmacy'
      WHERE NOT EXISTS(
        SELECT 1 FROM public.invoice_items i
        WHERE i.source_type='prescription' AND i.source_id=r.id
      );
    END LOOP;
  END IF;

  SELECT st.amount INTO tariff
  FROM public.service_tariffs st
  WHERE st.service_code='WARD-ACCOM'
    AND st.active
    AND st.effective_from<=_to::date
    AND (st.effective_to IS NULL OR st.effective_to>=_from::date)
  ORDER BY st.effective_from DESC NULLS LAST
  LIMIT 1;

  IF tariff IS NOT NULL AND to_regclass('public.admissions') IS NOT NULL THEN
    FOR r IN
      SELECT a.id,a.admitted_at,a.discharged_at,a.ward
      FROM public.admissions a
      WHERE a.patient_id=_patient_id
        AND a.admitted_at<=_to
        AND pg_catalog.coalesce(a.discharged_at,_to)>=_from
    LOOP
      days_count:=pg_catalog.greatest(
        1,
        pg_catalog.ceil(
          extract(epoch from(
            pg_catalog.least(pg_catalog.coalesce(r.discharged_at,_to),_to) -
            pg_catalog.greatest(r.admitted_at,_from)
          ))/86400
        )::integer
      );
      INSERT INTO public.invoice_items(
        invoice_id,description,quantity,unit_price,amount,category,
        source_type,source_id,service_code,department
      )
      SELECT
        inv,'Accommodation: '||pg_catalog.coalesce(r.ward,'Ward'),
        days_count,tariff,days_count*tariff,'ward',
        'admission',r.id,'WARD-ACCOM','ward'
      WHERE NOT EXISTS(
        SELECT 1 FROM public.invoice_items i
        WHERE i.source_type='admission' AND i.source_id=r.id
      );
    END LOOP;
  END IF;

  UPDATE public.invoices
  SET total_amount=pg_catalog.coalesce(
        (SELECT sum(ii.amount) FROM public.invoice_items ii WHERE ii.invoice_id=inv),0
      ),
      updated_at=pg_catalog.now()
  WHERE id=inv;

  RETURN QUERY
  SELECT
    ii.invoice_id,
    ii.id,
    ii.source_type,
    ii.source_id,
    ii.description,
    ii.category,
    ii.department,
    ii.quantity,
    ii.unit_price,
    ii.amount,
    pg_catalog.coalesce(
      (SELECT sum(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0
    ),
    pg_catalog.greatest(
      ii.amount-pg_catalog.coalesce(
        (SELECT sum(ip.amount) FROM public.invoice_item_payments ip WHERE ip.invoice_item_id=ii.id),0
      ),0
    ),
    so.id,
    so.status
  FROM public.invoice_items ii
  LEFT JOIN LATERAL(
    SELECT s.id,s.status
    FROM public.service_orders s
    WHERE s.invoice_item_id=ii.id
    ORDER BY s.created_at DESC
    LIMIT 1
  ) so ON true
  WHERE ii.invoice_id=inv
  ORDER BY ii.created_at;
END;
$function$;

REVOKE ALL ON FUNCTION public.mark_meal_order_delivered(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_meal_order_delivered(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_meal_order_delivered(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.record_patient_deposit(uuid,numeric,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_patient_deposit(uuid,numeric,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.record_patient_deposit(uuid,numeric,text) TO authenticated;

REVOKE ALL ON FUNCTION public.prepare_patient_billable_items(uuid,timestamptz,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prepare_patient_billable_items(uuid,timestamptz,timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.prepare_patient_billable_items(uuid,timestamptz,timestamptz) TO authenticated;
