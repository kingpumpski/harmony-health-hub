-- Harden bill materialization patient context and deterministic service-order linkage.
-- Branch-only migration; production is unchanged until explicitly deployed.

CREATE OR REPLACE FUNCTION public.prepare_patient_billable_items(
  _patient_id uuid,
  _from timestamptz DEFAULT date_trunc('day',now()),
  _to timestamptz DEFAULT now()
)
RETURNS TABLE(
  invoice_id uuid, invoice_item_id uuid, source_type text, source_id uuid,
  description text, category text, department text, quantity integer,
  unit_price numeric, amount numeric, paid_amount numeric,
  outstanding_amount numeric, service_order_id uuid, service_order_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  inv UUID;
  tariff NUMERIC;
  r RECORD;
  days_count INTEGER;
  uid UUID := auth.uid();
BEGIN
  IF uid IS NULL OR NOT(
    public.has_role(uid,'admin')
    OR public.has_role(uid,'accountant')
    OR public.has_role(uid,'front_desk')
  ) THEN
    RAISE EXCEPTION 'Billing access denied';
  END IF;

  IF _patient_id IS NULL OR _from IS NULL OR _to IS NULL OR _from > _to THEN
    RAISE EXCEPTION 'Invalid patient billing period';
  END IF;

  IF NOT EXISTS(SELECT 1 FROM public.patients WHERE id=_patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(_patient_id::text,0));

  SELECT id INTO inv
  FROM public.invoices
  WHERE patient_id=_patient_id AND status IN('pending','partially_paid')
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF inv IS NULL THEN
    INSERT INTO public.invoices(invoice_number,patient_id,total_amount,created_by)
    VALUES(
      'INV-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS')||'-'||substr(gen_random_uuid()::text,1,6),
      _patient_id,0,uid
    )
    RETURNING id INTO inv;
  END IF;

  SELECT amount INTO tariff
  FROM public.service_tariffs
  WHERE service_code='CONSULTATION' AND active
  LIMIT 1;

  IF tariff IS NOT NULL THEN
    INSERT INTO public.invoice_items(
      invoice_id,patient_id,description,quantity,unit_price,amount,category,
      source_type,source_id,source_key,service_code,department
    )
    SELECT
      inv,_patient_id,'Consultation',1,tariff,tariff,'consultation',
      'appointment',a.id,'appointment:'||a.id::text,'CONSULTATION','consultation'
    FROM public.appointments a
    WHERE a.patient_id=_patient_id
      AND a.scheduled_at BETWEEN _from AND _to
      AND a.status NOT IN('cancelled','no_show')
      AND NOT EXISTS(
        SELECT 1 FROM public.invoice_items i
        WHERE i.source_key='appointment:'||a.id::text
      )
      AND NOT EXISTS(
        SELECT 1 FROM public.service_orders so
        WHERE so.patient_id=a.patient_id
          AND so.related_entity_id=a.id
          AND so.department='consultation'
          AND so.status<>'cancelled'
      );
  END IF;

  SELECT amount INTO tariff
  FROM public.service_tariffs
  WHERE service_code='LAB-GENERIC' AND active
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
        invoice_id,patient_id,description,quantity,unit_price,amount,category,
        source_type,source_id,source_key,service_code,department
      )
      SELECT
        inv,_patient_id,r.test_name,1,tariff,tariff,'lab',
        'lab_order',r.id,'lab_order:'||r.id::text,'LAB-GENERIC','laboratory'
      WHERE NOT EXISTS(
        SELECT 1 FROM public.invoice_items i
        WHERE i.source_key='lab_order:'||r.id::text
      );
    END LOOP;
  END IF;

  SELECT amount INTO tariff
  FROM public.service_tariffs
  WHERE service_code='PROCEDURE-GENERIC' AND active
  LIMIT 1;

  FOR r IN
    SELECT so.id,so.service_name,so.amount,so.department,so.service_code,
           so.invoice_id,so.invoice_item_id
    FROM public.service_orders so
    WHERE so.patient_id=_patient_id
      AND so.created_at BETWEEN _from AND _to
      AND so.status<>'cancelled'
      AND so.invoice_item_id IS NULL
  LOOP
    IF r.invoice_id IS NOT NULL AND r.invoice_id IS DISTINCT FROM inv THEN
      RAISE EXCEPTION 'Service order % is linked to a different invoice',r.id;
    END IF;

    INSERT INTO public.invoice_items(
      invoice_id,patient_id,description,quantity,unit_price,amount,category,
      source_type,source_id,source_key,service_code,department,service_order_id
    )
    SELECT
      inv,_patient_id,r.service_name,1,
      COALESCE(r.amount,tariff,0),
      COALESCE(r.amount,tariff,0),
      CASE
        WHEN r.department='pharmacy' THEN 'pharmacy'
        WHEN r.department='laboratory' THEN 'lab'
        WHEN r.department IN('imaging','radiology') THEN 'imaging'
        ELSE 'procedure'
      END,
      'service_order',r.id,'service_order:'||r.id::text,
      COALESCE(r.service_code,'PROCEDURE-GENERIC'),r.department,r.id
    WHERE NOT EXISTS(
      SELECT 1 FROM public.invoice_items i
      WHERE i.source_key='service_order:'||r.id::text
    )
    RETURNING id INTO r.invoice_item_id;

    IF r.invoice_item_id IS NOT NULL THEN
      UPDATE public.service_orders
      SET invoice_id=inv,
          invoice_item_id=r.invoice_item_id,
          updated_at=now()
      WHERE id=r.id
        AND patient_id=_patient_id
        AND (invoice_id IS NULL OR invoice_id=inv)
        AND invoice_item_id IS NULL;
    END IF;
  END LOOP;

  SELECT amount INTO tariff
  FROM public.service_tariffs
  WHERE service_code='PROCEDURE-GENERIC' AND active
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
        invoice_id,patient_id,description,quantity,unit_price,amount,category,
        source_type,source_id,source_key,service_code,department
      )
      SELECT
        inv,_patient_id,'Medication: '||r.medication,
        GREATEST(COALESCE(NULLIF(r.computed_quantity,0),1),1),
        tariff,
        GREATEST(COALESCE(NULLIF(r.computed_quantity,0),1),1)*tariff,
        'pharmacy','prescription',r.id,'prescription:'||r.id::text,
        'PROCEDURE-GENERIC','pharmacy'
      WHERE NOT EXISTS(
        SELECT 1 FROM public.invoice_items i
        WHERE i.source_key='prescription:'||r.id::text
      );
    END LOOP;
  END IF;

  SELECT amount INTO tariff
  FROM public.service_tariffs
  WHERE service_code='WARD-ACCOM' AND active
  LIMIT 1;

  IF tariff IS NOT NULL AND to_regclass('public.admissions') IS NOT NULL THEN
    FOR r IN
      SELECT a.id,a.admitted_at,a.discharged_at,a.ward
      FROM public.admissions a
      WHERE a.patient_id=_patient_id
        AND a.admitted_at<=_to
        AND COALESCE(a.discharged_at,_to)>=_from
    LOOP
      days_count:=GREATEST(
        1,
        CEIL(
          EXTRACT(EPOCH FROM(
            LEAST(COALESCE(r.discharged_at,_to),_to)
            - GREATEST(r.admitted_at,_from)
          ))/86400
        )::INTEGER
      );

      INSERT INTO public.invoice_items(
        invoice_id,patient_id,description,quantity,unit_price,amount,category,
        source_type,source_id,source_key,service_code,department
      )
      SELECT
        inv,_patient_id,'Accommodation: '||COALESCE(r.ward,'Ward'),
        days_count,tariff,days_count*tariff,'ward',
        'admission',r.id,'admission:'||r.id::text,'WARD-ACCOM','ward'
      WHERE NOT EXISTS(
        SELECT 1 FROM public.invoice_items i
        WHERE i.source_key='admission:'||r.id::text
      );
    END LOOP;
  END IF;

  UPDATE public.invoices
  SET total_amount=COALESCE(
    (SELECT SUM(ii.amount) FROM public.invoice_items ii WHERE ii.invoice_id=inv),0
  ),
  updated_at=now()
  WHERE id=inv;

  RETURN QUERY
  SELECT
    ii.invoice_id,ii.id,ii.source_type,ii.source_id,ii.description,ii.category,
    ii.department,ii.quantity,ii.unit_price,ii.amount,
    COALESCE(
      (SELECT SUM(ip.amount)
       FROM public.invoice_item_payments ip
       WHERE ip.invoice_item_id=ii.id),0
    ),
    GREATEST(
      ii.amount-COALESCE(
        (SELECT SUM(ip.amount)
         FROM public.invoice_item_payments ip
         WHERE ip.invoice_item_id=ii.id),0
      ),0
    ),
    so.id,so.status
  FROM public.invoice_items ii
  LEFT JOIN LATERAL(
    SELECT s.id,s.status
    FROM public.service_orders s
    WHERE s.invoice_item_id=ii.id
      AND s.patient_id=_patient_id
    ORDER BY s.created_at DESC
    LIMIT 1
  ) so ON true
  WHERE ii.invoice_id=inv
    AND (ii.patient_id IS NULL OR ii.patient_id=_patient_id)
  ORDER BY ii.created_at;
END;
$function$;

REVOKE ALL ON FUNCTION public.prepare_patient_billable_items(uuid,timestamptz,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_patient_billable_items(uuid,timestamptz,timestamptz) TO authenticated;
