-- Allow pharmacy catalogue managers to update the shared category while stock fields remain facility-scoped.
DROP FUNCTION IF EXISTS public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric);
DROP FUNCTION IF EXISTS public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text);
DROP FUNCTION IF EXISTS public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric);
CREATE OR REPLACE FUNCTION public.assign_unattributed_pharmacy_inventory(
  _item_id uuid, _reason text
)
RETURNS public.pharmacy_inventory
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE r public.pharmacy_inventory; uid uuid := auth.uid(); fid uuid := public.current_user_facility_id();
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid, 'admin') OR public.has_role(uid, 'system_superuser')) THEN
    RAISE EXCEPTION 'System administrator authorization is required to assign legacy stock';
  END IF;
  IF fid IS NULL THEN RAISE EXCEPTION 'Select the verified destination facility before assigning legacy stock'; END IF;
  IF pg_catalog.length(pg_catalog.btrim(coalesce(_reason, ''))) < 10 THEN
    RAISE EXCEPTION 'Record the stock reconciliation reason before assigning this item';
  END IF;
  UPDATE public.pharmacy_inventory SET facility_id = fid, updated_at = pg_catalog.now()
  WHERE id = _item_id AND facility_id IS NULL AND active RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unassigned inventory item was not found or has already been assigned'; END IF;
  PERFORM public.record_system_audit('pharmacy_legacy_stock_facility_assigned', 'pharmacy',
    'pharmacy_inventory', r.id, 'warning', pg_catalog.jsonb_build_object(
      'drug_name', r.drug_name, 'facility_id', fid, 'reason', pg_catalog.btrim(_reason), 'actor_id', uid));
  RETURN r;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'This would create a duplicate base catalogue item in the selected facility. Reconcile the existing item and batch records before assigning it.';
END;
$function$;
REVOKE ALL ON FUNCTION public.assign_unattributed_pharmacy_inventory(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_unattributed_pharmacy_inventory(uuid,text) TO authenticated;

CREATE FUNCTION public.update_pharmacy_inventory_item(
  _item_id uuid, _drug_name text, _brand_name text, _generic_name text, _strength text,
  _form text, _supplier text, _batch_number text, _expiry_date date, _stock_quantity integer,
  _reorder_level integer, _unit_price numeric, _barcode text DEFAULT NULL,
  _nhis_patient_price numeric DEFAULT 0, _nhis_claim_amount numeric DEFAULT 0,
  _category text DEFAULT NULL
)
RETURNS public.pharmacy_inventory LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE r public.pharmacy_inventory; v_uid uuid := auth.uid(); v_facility uuid := public.current_user_facility_id();
BEGIN
  IF v_uid IS NULL OR NOT (public.has_role(v_uid, 'admin') OR public.has_role(v_uid, 'it_admin')
    OR public.has_role(v_uid, 'system_superuser') OR public.has_role(v_uid, 'pharmacist')
    OR public.current_user_has_catalogue_create_permission('create_items')) THEN
    RAISE EXCEPTION 'Pharmacy inventory management permission required';
  END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before updating stock'; END IF;
  IF _item_id IS NULL THEN RAISE EXCEPTION 'Inventory item is required'; END IF;
  IF pg_catalog.length(pg_catalog.btrim(COALESCE(_drug_name, ''))) < 2 THEN RAISE EXCEPTION 'Drug name must contain at least two characters'; END IF;
  IF COALESCE(_stock_quantity, 0) < 0 OR COALESCE(_reorder_level, 0) < 0
    OR COALESCE(_unit_price, 0) < 0 OR COALESCE(_nhis_patient_price, 0) < 0
    OR COALESCE(_nhis_claim_amount, 0) < 0 THEN RAISE EXCEPTION 'Inventory values cannot be negative'; END IF;
  IF _expiry_date IS NOT NULL AND _expiry_date < CURRENT_DATE THEN RAISE EXCEPTION 'Expiry date cannot be in the past'; END IF;
  IF COALESCE(_stock_quantity, 0) > 0 AND (_expiry_date IS NULL OR COALESCE(_unit_price, 0) <= 0 OR COALESCE(_reorder_level, 0) <= 0) THEN
    RAISE EXCEPTION 'Expiry date, positive retail price and a configured reorder level are required before stock can be made available';
  END IF;
  UPDATE public.pharmacy_inventory SET
    brand_name = NULLIF(pg_catalog.btrim(_brand_name), ''),
    supplier = NULLIF(pg_catalog.btrim(_supplier), ''), batch_number = NULLIF(pg_catalog.btrim(_batch_number), ''),
    expiry_date = _expiry_date, stock_quantity = COALESCE(_stock_quantity, 0),
    reorder_level = COALESCE(_reorder_level, 0), unit_price = COALESCE(_unit_price, 0),
    barcode = NULLIF(pg_catalog.btrim(_barcode), ''),
    nhis_patient_price = COALESCE(_nhis_patient_price, 0),
    nhis_claim_amount = COALESCE(_nhis_claim_amount, 0),
    updated_at = pg_catalog.now()
  WHERE id = _item_id AND facility_id = v_facility AND active RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active pharmacy inventory item was not found in the active facility'; END IF;
  IF r.catalogue_id IS NOT NULL AND NULLIF(pg_catalog.btrim(_category), '') IS NOT NULL THEN
    UPDATE public.medication_catalogue SET category = pg_catalog.btrim(_category), updated_at = pg_catalog.now()
    WHERE id = r.catalogue_id;
  END IF;
  PERFORM public.record_system_audit('pharmacy_inventory_updated', 'pharmacy', 'pharmacy_inventory', r.id, 'info',
    pg_catalog.jsonb_build_object('drug_name', r.drug_name, 'stock_quantity', r.stock_quantity,
      'facility_id', v_facility, 'actor_id', v_uid));
  RETURN r;
END;
$function$;
REVOKE ALL ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text) TO authenticated;


NOTIFY pgrst, 'reload schema';
