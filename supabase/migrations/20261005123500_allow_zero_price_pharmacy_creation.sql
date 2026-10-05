-- Follow-up to runtime pharmacy hardening: allow zero-price/reorder stock creation.
CREATE OR REPLACE FUNCTION public.create_pharmacy_inventory_item(
  _drug_name text,_brand_name text,_generic_name text,_strength text,_form text,
  _supplier text,_batch_number text,_expiry_date date,_stock_quantity integer,
  _reorder_level integer,_unit_price numeric,_category text DEFAULT 'Uncategorized'
)
RETURNS public.pharmacy_inventory
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  result public.pharmacy_inventory;
  v_uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_catalogue_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT (
    public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin')
    OR public.has_role(v_uid,'system_superuser') OR public.has_role(v_uid,'pharmacist')
    OR public.current_user_has_catalogue_create_permission('create_items')
  ) THEN RAISE EXCEPTION 'Pharmacy inventory management permission required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before adding medication to the store'; END IF;
  IF pg_catalog.length(pg_catalog.btrim(coalesce(_drug_name,''))) < 2 THEN RAISE EXCEPTION 'Drug name must contain at least two characters'; END IF;
  IF coalesce(_stock_quantity,0) < 0 OR coalesce(_reorder_level,0) < 0 OR coalesce(_unit_price,0) < 0 THEN RAISE EXCEPTION 'Inventory values cannot be negative'; END IF;
  IF _expiry_date IS NOT NULL AND _expiry_date < CURRENT_DATE THEN RAISE EXCEPTION 'Expiry date cannot be in the past'; END IF;
  IF coalesce(_stock_quantity,0) > 0 AND _expiry_date IS NULL THEN RAISE EXCEPTION 'Expiry date is required before stock can be made available'; END IF;

  INSERT INTO public.medication_catalogue(name,category,generic_name,strength,form,created_by)
  VALUES (pg_catalog.btrim(_drug_name),coalesce(nullif(pg_catalog.btrim(_category),''),'Uncategorized'),
    nullif(pg_catalog.btrim(_generic_name),''),nullif(pg_catalog.btrim(_strength),''),
    nullif(pg_catalog.btrim(_form),''),v_uid)
  ON CONFLICT DO NOTHING;

  SELECT c.id INTO v_catalogue_id FROM public.medication_catalogue c
  WHERE lower(btrim(c.name))=lower(btrim(_drug_name))
    AND lower(btrim(coalesce(c.generic_name,'')))=lower(btrim(coalesce(_generic_name,'')))
    AND lower(btrim(coalesce(c.strength,'')))=lower(btrim(coalesce(_strength,'')))
    AND lower(btrim(coalesce(c.form,'')))=lower(btrim(coalesce(_form,'')))
  LIMIT 1;
  IF v_catalogue_id IS NULL THEN RAISE EXCEPTION 'Could not resolve global medication catalogue entry'; END IF;

  INSERT INTO public.pharmacy_inventory(
    catalogue_id,facility_id,drug_name,brand_name,generic_name,strength,form,supplier,
    batch_number,expiry_date,stock_quantity,reorder_level,unit_price,nhis_patient_price,
    nhis_claim_amount,active
  ) VALUES (
    v_catalogue_id,v_facility,pg_catalog.btrim(_drug_name),nullif(pg_catalog.btrim(_brand_name),''),
    nullif(pg_catalog.btrim(_generic_name),''),nullif(pg_catalog.btrim(_strength),''),
    nullif(pg_catalog.btrim(_form),''),nullif(pg_catalog.btrim(_supplier),''),
    nullif(pg_catalog.btrim(_batch_number),''),_expiry_date,coalesce(_stock_quantity,0),
    coalesce(_reorder_level,0),coalesce(_unit_price,0),0,0,true
  ) RETURNING * INTO result;

  PERFORM public.record_system_audit('pharmacy_inventory_created','pharmacy','pharmacy_inventory',
    result.id,'info',pg_catalog.jsonb_build_object('drug_name',result.drug_name,
    'stock_quantity',result.stock_quantity,'facility_id',v_facility,'catalogue_id',v_catalogue_id,
    'actor_id',v_uid));
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'This medication is already in the facility store. Select it and edit the existing stock item.';
END;
$function$;

REVOKE ALL ON FUNCTION public.create_pharmacy_inventory_item(text,text,text,text,text,text,text,date,integer,integer,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_inventory_item(text,text,text,text,text,text,text,date,integer,integer,numeric,text) TO authenticated;
NOTIFY pgrst,'reload schema';
