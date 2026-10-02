-- Restore pharmacy-store access for authorized catalogue managers and add audited inventory updates.
-- The medication catalogue remains global in the current schema; this migration does not grant catalogue-only users access to patient clinical data.

CREATE OR REPLACE FUNCTION public.get_pharmacy_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  result jsonb;
  v_uid uuid := auth.uid();
  v_department text;
  v_facility uuid := public.current_user_facility_id();
  v_admin boolean;
  v_pharmacist boolean;
  v_front_desk boolean;
  v_catalogue_manager boolean;
  v_clinical_pharmacy boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  v_admin := public.has_role(v_uid, 'admin');
  v_pharmacist := public.has_role(v_uid, 'pharmacist');
  v_front_desk := public.has_role(v_uid, 'front_desk');
  v_catalogue_manager := public.has_role(v_uid, 'it_admin')
    OR public.has_role(v_uid, 'system_superuser')
    OR public.current_user_has_catalogue_create_permission('create_items');
  v_clinical_pharmacy := v_admin OR v_pharmacist;

  SELECT NULLIF(pg_catalog.lower(pg_catalog.btrim(p.department)), '')
    INTO v_department
    FROM public.profiles p
    WHERE p.id = v_uid;

  IF v_pharmacist AND v_department IS NOT NULL AND v_department <> 'pharmacy' THEN
    RAISE EXCEPTION 'Pharmacy workspace access is not permitted for this department';
  END IF;

  IF v_front_desk AND v_department IS NOT NULL
     AND v_department NOT IN ('pharmacy', 'front desk', 'front_desk') THEN
    RAISE EXCEPTION 'Pharmacy workspace access is not permitted for this department';
  END IF;

  IF NOT (v_admin OR v_pharmacist OR v_front_desk OR v_catalogue_manager) THEN
    RAISE EXCEPTION 'Pharmacy workspace access is not permitted';
  END IF;

  _limit := LEAST(GREATEST(COALESCE(_limit, 200), 1), 500);

  SELECT pg_catalog.jsonb_build_object(
    'patients', CASE WHEN v_admin OR v_pharmacist OR v_front_desk THEN
      COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.first_name, p.last_name)
        FROM (
          SELECT p.id, p.first_name, p.last_name, p.patient_code
          FROM public.patients p
          WHERE COALESCE(p.status, 'active') <> 'inactive'
            AND (v_admin OR (v_facility IS NOT NULL AND p.facility_id = v_facility))
          ORDER BY p.first_name, p.last_name
          LIMIT _limit
        ) p
      ), '[]'::jsonb)
      ELSE '[]'::jsonb END,
    'inventory', COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.drug_name)
      FROM (
        SELECT i.id, i.drug_name, i.brand_name, i.generic_name, i.form, i.strength,
          i.stock_quantity, i.reorder_level, i.unit_price, i.supplier, i.batch_number, i.expiry_date
        FROM public.pharmacy_inventory i
        WHERE i.active
        ORDER BY i.drug_name
        LIMIT _limit
      ) i
    ), '[]'::jsonb),
    'prescriptions', CASE WHEN v_clinical_pharmacy THEN
      COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) ORDER BY x.created_at DESC)
        FROM (
          SELECT r.id, r.patient_id, r.medication, r.dosage, r.frequency, r.duration,
            r.computed_quantity, r.status, r.created_at,
            pg_catalog.jsonb_build_object('id', p.id, 'first_name', p.first_name,
              'last_name', p.last_name, 'patient_code', p.patient_code) AS patients
          FROM public.prescriptions r
          JOIN public.patients p ON p.id = r.patient_id
          WHERE r.status IN ('pending', 'paid')
            AND (v_admin OR (v_facility IS NOT NULL AND p.facility_id = v_facility))
          ORDER BY r.created_at DESC
          LIMIT _limit
        ) x
      ), '[]'::jsonb)
      ELSE '[]'::jsonb END,
    'plans', CASE WHEN v_clinical_pharmacy THEN
      COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) ORDER BY x.created_at DESC)
        FROM (
          SELECT d.id, d.patient_id, d.medication_name, d.prepared_quantity, d.service_order_id,
            d.status, d.created_at, so.status AS service_order_status,
            pg_catalog.jsonb_build_object('id', p.id, 'first_name', p.first_name,
              'last_name', p.last_name, 'patient_code', p.patient_code) AS patients
          FROM public.pharmacy_dispensing_plans d
          JOIN public.patients p ON p.id = d.patient_id
          LEFT JOIN public.service_orders so ON so.id = d.service_order_id
          WHERE d.status <> 'cancelled'
            AND (v_admin OR (v_facility IS NOT NULL AND p.facility_id = v_facility))
          ORDER BY d.created_at DESC
          LIMIT _limit
        ) x
      ), '[]'::jsonb)
      ELSE '[]'::jsonb END,
    'pos_sales', CASE WHEN v_admin OR v_pharmacist OR v_front_desk THEN
      COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) ORDER BY x.created_at DESC)
        FROM (
          SELECT s.id, s.patient_id, s.medication, s.quantity, s.total_amount, s.status,
            s.service_order_id, s.created_at, COALESCE(so.status, s.status) AS effective_status
          FROM public.pharmacy_pos_sales s
          LEFT JOIN public.service_orders so ON so.id = s.service_order_id
          WHERE s.status NOT IN ('dispensed', 'cancelled')
            AND (v_admin OR (v_facility IS NOT NULL AND s.facility_id = v_facility))
          ORDER BY s.created_at DESC
          LIMIT _limit
        ) x
      ), '[]'::jsonb)
      ELSE '[]'::jsonb END
  ) INTO result;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_pharmacy_workspace(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pharmacy_workspace(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_pharmacy_inventory_item(
  _item_id uuid,
  _drug_name text,
  _brand_name text,
  _generic_name text,
  _strength text,
  _form text,
  _supplier text,
  _batch_number text,
  _expiry_date date,
  _stock_quantity integer,
  _reorder_level integer,
  _unit_price numeric
)
RETURNS public.pharmacy_inventory
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  r public.pharmacy_inventory;
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT (
    public.has_role(v_uid, 'admin')
    OR public.has_role(v_uid, 'it_admin')
    OR public.has_role(v_uid, 'system_superuser')
    OR public.has_role(v_uid, 'pharmacist')
    OR public.current_user_has_catalogue_create_permission('create_items')
  ) THEN
    RAISE EXCEPTION 'Pharmacy inventory management permission required';
  END IF;

  IF _item_id IS NULL THEN
    RAISE EXCEPTION 'Inventory item is required';
  END IF;
  IF pg_catalog.length(pg_catalog.btrim(COALESCE(_drug_name, ''))) < 2 THEN
    RAISE EXCEPTION 'Drug name must contain at least two characters';
  END IF;
  IF COALESCE(_stock_quantity, 0) < 0
     OR COALESCE(_reorder_level, 0) < 0
     OR COALESCE(_unit_price, 0) < 0 THEN
    RAISE EXCEPTION 'Inventory values cannot be negative';
  END IF;
  IF _expiry_date IS NOT NULL AND _expiry_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Expiry date cannot be in the past';
  END IF;
  IF COALESCE(_unit_price, 0) = 0 AND COALESCE(_stock_quantity, 0) > 0 THEN
    RAISE EXCEPTION 'Unit price is required for stocked inventory';
  END IF;

  UPDATE public.pharmacy_inventory
  SET drug_name = pg_catalog.btrim(_drug_name),
      brand_name = NULLIF(pg_catalog.btrim(_brand_name), ''),
      generic_name = NULLIF(pg_catalog.btrim(_generic_name), ''),
      strength = NULLIF(pg_catalog.btrim(_strength), ''),
      form = NULLIF(pg_catalog.btrim(_form), ''),
      supplier = NULLIF(pg_catalog.btrim(_supplier), ''),
      batch_number = NULLIF(pg_catalog.btrim(_batch_number), ''),
      expiry_date = _expiry_date,
      stock_quantity = COALESCE(_stock_quantity, 0),
      reorder_level = COALESCE(_reorder_level, 0),
      unit_price = COALESCE(_unit_price, 0),
      updated_at = pg_catalog.now()
  WHERE id = _item_id AND active
  RETURNING * INTO r;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active pharmacy inventory item was not found';
  END IF;

  PERFORM public.record_system_audit(
    'pharmacy_inventory_updated', 'pharmacy', 'pharmacy_inventory', r.id, 'info',
    pg_catalog.jsonb_build_object('drug_name', r.drug_name, 'stock_quantity', r.stock_quantity, 'actor_id', v_uid)
  );
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric) TO authenticated;
