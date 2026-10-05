-- Runtime/UAT reconciliation: one facility-aware patient directory plus pharmacy zero-price edits.

CREATE OR REPLACE FUNCTION public.create_pharmacy_inventory_item(
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
  _unit_price numeric,
  _category text DEFAULT 'Uncategorized'
)
RETURNS public.pharmacy_inventory
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  result public.pharmacy_inventory;
  v_uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_catalogue_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT (
    public.has_role(v_uid,'admin')
    OR public.has_role(v_uid,'it_admin')
    OR public.has_role(v_uid,'system_superuser')
    OR public.has_role(v_uid,'pharmacist')
    OR public.current_user_has_catalogue_create_permission('create_items')
  ) THEN
    RAISE EXCEPTION 'Pharmacy inventory management permission required';
  END IF;

  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before adding medication to the store'; END IF;
  IF pg_catalog.length(pg_catalog.btrim(coalesce(_drug_name,''))) < 2 THEN
    RAISE EXCEPTION 'Drug name must contain at least two characters';
  END IF;
  IF coalesce(_stock_quantity,0) < 0 OR coalesce(_reorder_level,0) < 0 OR coalesce(_unit_price,0) < 0 THEN
    RAISE EXCEPTION 'Inventory values cannot be negative';
  END IF;
  IF _expiry_date IS NOT NULL AND _expiry_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Expiry date cannot be in the past';
  END IF;
  -- Zero price and zero reorder values are valid for test/preconfigured stock.
  -- Stock that is actually entered still requires an expiry date.
  IF coalesce(_stock_quantity,0) > 0 AND _expiry_date IS NULL THEN
    RAISE EXCEPTION 'Expiry date is required before stock can be made available';
  END IF;

  INSERT INTO public.medication_catalogue(name,category,generic_name,strength,form,created_by)
  VALUES (
    pg_catalog.btrim(_drug_name),
    coalesce(nullif(pg_catalog.btrim(_category),''),'Uncategorized'),
    nullif(pg_catalog.btrim(_generic_name),''),
    nullif(pg_catalog.btrim(_strength),''),
    nullif(pg_catalog.btrim(_form),''),
    v_uid
  )
  ON CONFLICT DO NOTHING;

  SELECT c.id INTO v_catalogue_id
  FROM public.medication_catalogue c
  WHERE lower(btrim(c.name))=lower(btrim(_drug_name))
    AND lower(btrim(coalesce(c.generic_name,'')))=lower(btrim(coalesce(_generic_name,'')))
    AND lower(btrim(coalesce(c.strength,'')))=lower(btrim(coalesce(_strength,'')))
    AND lower(btrim(coalesce(c.form,'')))=lower(btrim(coalesce(_form,'')))
  LIMIT 1;

  IF v_catalogue_id IS NULL THEN RAISE EXCEPTION 'Could not resolve global medication catalogue entry'; END IF;

  INSERT INTO public.pharmacy_inventory(
    catalogue_id,facility_id,drug_name,brand_name,generic_name,strength,form,
    supplier,batch_number,expiry_date,stock_quantity,reorder_level,unit_price,
    nhis_patient_price,nhis_claim_amount,active
  ) VALUES (
    v_catalogue_id,v_facility,pg_catalog.btrim(_drug_name),
    nullif(pg_catalog.btrim(_brand_name),''),
    nullif(pg_catalog.btrim(_generic_name),''),
    nullif(pg_catalog.btrim(_strength),''),
    nullif(pg_catalog.btrim(_form),''),
    nullif(pg_catalog.btrim(_supplier),''),
    nullif(pg_catalog.btrim(_batch_number),''),
    _expiry_date,coalesce(_stock_quantity,0),coalesce(_reorder_level,0),
    coalesce(_unit_price,0),0,0,true
  )
  RETURNING * INTO result;

  PERFORM public.record_system_audit(
    'pharmacy_inventory_created','pharmacy','pharmacy_inventory',result.id,'info',
    pg_catalog.jsonb_build_object(
      'drug_name',result.drug_name,'stock_quantity',result.stock_quantity,
      'facility_id',v_facility,'catalogue_id',v_catalogue_id,'actor_id',v_uid
    )
  );
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'This medication is already in the facility store. Select it and edit the existing stock item.';
END;
$function$;

REVOKE ALL ON FUNCTION public.create_pharmacy_inventory_item(text,text,text,text,text,text,text,date,integer,integer,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_inventory_item(text,text,text,text,text,text,text,date,integer,integer,numeric,text) TO authenticated;

-- Test users resolve through current_user_facility_id(), which already routes test mode
-- to the configured Harmony Health Hub Test Facility.

DROP FUNCTION IF EXISTS public.get_patient_directory(text, integer);

CREATE FUNCTION public.get_patient_directory(
  _query text DEFAULT NULL,
  _limit integer DEFAULT 300
)
RETURNS TABLE(
  id uuid,
  patient_code text,
  first_name text,
  last_name text,
  phone text,
  ghana_card_number text,
  status text,
  insurance_provider text,
  insurance_number text,
  membership_type text,
  membership_expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  active_facility uuid := public.current_user_facility_id();
  q text := NULLIF(pg_catalog.btrim(coalesce(_query,'')), '');
  lim integer := least(greatest(coalesce(_limit,300),1),1000);
  is_admin boolean;
  can_sensitive boolean;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  IF NOT (
    public.has_role(uid,'admin'::public.app_role)
    OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'system_superuser'::public.app_role)
    OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role)
    OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
    OR public.has_role(uid,'lab_technician'::public.app_role)
    OR public.has_role(uid,'radiologist'::public.app_role)
    OR public.has_role(uid,'radiology_technician'::public.app_role)
    OR public.has_role(uid,'pharmacist'::public.app_role)
    OR public.has_role(uid,'accountant'::public.app_role)
    OR public.has_role(uid,'front_desk'::public.app_role)
    OR public.has_role(uid,'canteen'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Not authorized to access the staff patient directory';
  END IF;

  is_admin := public.has_role(uid,'admin'::public.app_role)
    OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'system_superuser'::public.app_role);

  IF active_facility IS NULL THEN
    RAISE EXCEPTION 'An active facility is required to search patient records';
  END IF;

  can_sensitive := is_admin
    OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role)
    OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
    OR public.has_role(uid,'accountant'::public.app_role)
    OR public.has_role(uid,'front_desk'::public.app_role);

  RETURN QUERY
  SELECT
    p.id,
    p.patient_code,
    p.first_name,
    p.last_name,
    p.phone,
    CASE WHEN can_sensitive THEN p.ghana_card_number ELSE NULL END,
    p.status::text,
    CASE WHEN can_sensitive THEN p.insurance_provider ELSE NULL END,
    CASE WHEN can_sensitive THEN p.insurance_number ELSE NULL END,
    CASE WHEN can_sensitive THEN p.membership_type ELSE NULL END,
    CASE WHEN can_sensitive THEN p.membership_expires_at ELSE NULL END
  FROM public.patients p
  WHERE coalesce(p.status,'active') <> 'inactive'
    AND p.facility_id = active_facility
    AND (
      q IS NULL
      OR p.patient_code ILIKE '%' || q || '%'
      OR p.first_name ILIKE '%' || q || '%'
      OR p.last_name ILIKE '%' || q || '%'
      OR p.phone ILIKE '%' || q || '%'
      OR p.ghana_card_number ILIKE '%' || q || '%'
      OR p.email ILIKE '%' || q || '%'
    )
  ORDER BY p.created_at DESC
  LIMIT lim;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_patient_directory(text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_patient_directory(text,integer) TO authenticated;

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
  _unit_price numeric,
  _barcode text DEFAULT NULL,
  _nhis_patient_price numeric DEFAULT 0,
  _nhis_claim_amount numeric DEFAULT 0,
  _category text DEFAULT NULL
)
RETURNS public.pharmacy_inventory
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  r public.pharmacy_inventory;
  v_uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
BEGIN
  IF v_uid IS NULL OR NOT (
    public.has_role(v_uid,'admin')
    OR public.has_role(v_uid,'it_admin')
    OR public.has_role(v_uid,'system_superuser')
    OR public.has_role(v_uid,'pharmacist')
    OR public.current_user_has_catalogue_create_permission('create_items')
  ) THEN
    RAISE EXCEPTION 'Pharmacy inventory management permission required';
  END IF;

  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before updating stock'; END IF;
  IF _item_id IS NULL THEN RAISE EXCEPTION 'Inventory item is required'; END IF;
  IF pg_catalog.length(pg_catalog.btrim(coalesce(_drug_name,''))) < 2 THEN
    RAISE EXCEPTION 'Drug name must contain at least two characters';
  END IF;
  IF coalesce(_stock_quantity,0) < 0
    OR coalesce(_reorder_level,0) < 0
    OR coalesce(_unit_price,0) < 0
    OR coalesce(_nhis_patient_price,0) < 0
    OR coalesce(_nhis_claim_amount,0) < 0 THEN
    RAISE EXCEPTION 'Inventory values cannot be negative';
  END IF;
  IF _expiry_date IS NOT NULL AND _expiry_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Expiry date cannot be in the past';
  END IF;
  -- Zero price and zero reorder values are valid for test/preconfigured stock.
  -- Safety validation remains for stock that is actually made available.
  IF coalesce(_stock_quantity,0) > 0 AND _expiry_date IS NULL THEN
    RAISE EXCEPTION 'Expiry date is required before stock can be made available';
  END IF;

  UPDATE public.pharmacy_inventory
  SET drug_name=pg_catalog.btrim(_drug_name),
      brand_name=NULLIF(pg_catalog.btrim(_brand_name),''),
      generic_name=NULLIF(pg_catalog.btrim(_generic_name),''),
      strength=NULLIF(pg_catalog.btrim(_strength),''),
      form=NULLIF(pg_catalog.btrim(_form),''),
      supplier=NULLIF(pg_catalog.btrim(_supplier),''),
      batch_number=NULLIF(pg_catalog.btrim(_batch_number),''),
      expiry_date=_expiry_date,
      stock_quantity=coalesce(_stock_quantity,0),
      reorder_level=coalesce(_reorder_level,0),
      unit_price=coalesce(_unit_price,0),
      barcode=NULLIF(pg_catalog.btrim(_barcode),''),
      nhis_patient_price=coalesce(_nhis_patient_price,0),
      nhis_claim_amount=coalesce(_nhis_claim_amount,0),
      updated_at=pg_catalog.now()
  WHERE id=_item_id AND facility_id=v_facility AND active
  RETURNING * INTO r;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active pharmacy inventory item was not found in the active facility';
  END IF;

  IF r.catalogue_id IS NOT NULL AND NULLIF(pg_catalog.btrim(_category),'') IS NOT NULL THEN
    UPDATE public.medication_catalogue
    SET category=pg_catalog.btrim(_category), updated_at=pg_catalog.now()
    WHERE id=r.catalogue_id;
  END IF;

  PERFORM public.record_system_audit(
    'pharmacy_inventory_updated','pharmacy','pharmacy_inventory',r.id,'info',
    pg_catalog.jsonb_build_object(
      'drug_name',r.drug_name,
      'stock_quantity',r.stock_quantity,
      'unit_price',r.unit_price,
      'facility_id',v_facility,
      'actor_id',v_uid
    )
  );
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text) TO authenticated;

NOTIFY pgrst,'reload schema';
