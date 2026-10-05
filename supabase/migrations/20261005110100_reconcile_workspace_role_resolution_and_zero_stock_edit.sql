-- Reconcile workspace role resolution and preserve zero-stock pharmacy configuration edits.

DO $migration$
DECLARE src text; replacement text := $replacement$
SELECT CASE
  WHEN public.has_role(auth.uid(), 'system_superuser'::public.app_role) THEN 'system_superuser'
  WHEN public.has_role(auth.uid(), 'admin'::public.app_role) THEN 'admin'
  WHEN public.has_role(auth.uid(), 'it_admin'::public.app_role) THEN 'it_admin'
  WHEN public.has_role(auth.uid(), 'practitioner'::public.app_role) THEN 'practitioner'
  WHEN public.has_role(auth.uid(), 'nurse'::public.app_role) THEN 'nurse'
  WHEN public.has_role(auth.uid(), 'midwife'::public.app_role) THEN 'midwife'
  WHEN public.has_role(auth.uid(), 'specialist_nurse'::public.app_role) THEN 'specialist_nurse'
  ELSE NULL
END INTO v_role;$replacement$;
BEGIN
  SELECT pg_get_functiondef('public.get_admission_workspace(integer)'::regprocedure) INTO src;
  src := regexp_replace(src,'SELECT ur\\.role::text INTO v_role\\s+FROM public\\.user_roles ur\\s+WHERE ur\\.user_id=auth\\.uid\\(\\)\\s+ORDER BY ur\\.created_at DESC\\s+LIMIT 1;',replacement,'n');
  IF src IS NULL OR src = pg_get_functiondef('public.get_admission_workspace(integer)'::regprocedure) THEN RAISE EXCEPTION 'Admission workspace role-resolution pattern was not found'; END IF;
  EXECUTE src;
  SELECT pg_get_functiondef('public.get_ward_management_workspace(integer)'::regprocedure) INTO src;
  src := regexp_replace(src,'SELECT ur\\.role::text INTO v_role\\s+FROM public\\.user_roles ur\\s+WHERE ur\\.user_id=uid\\s+ORDER BY ur\\.created_at DESC\\s+LIMIT 1;',replace(replacement,'auth.uid()','uid'),'n');
  IF src IS NULL OR src = pg_get_functiondef('public.get_ward_management_workspace(integer)'::regprocedure) THEN RAISE EXCEPTION 'Ward workspace role-resolution pattern was not found'; END IF;
  EXECUTE src;
  SELECT pg_get_functiondef('public.get_operational_workspace(text,integer)'::regprocedure) INTO src;
  src := regexp_replace(src,'SELECT ur\\.role::text INTO v_role FROM public\\.user_roles ur WHERE ur\\.user_id=auth\\.uid\\(\\) ORDER BY ur\\.created_at DESC LIMIT 1;',replacement,'n');
  IF src IS NULL OR src = pg_get_functiondef('public.get_operational_workspace(text,integer)'::regprocedure) THEN RAISE EXCEPTION 'Operational workspace role-resolution pattern was not found'; END IF;
  EXECUTE src;
END
$migration$;

CREATE OR REPLACE FUNCTION public.update_pharmacy_inventory_item(
  _item_id uuid,_drug_name text,_brand_name text,_generic_name text,_strength text,_form text,_supplier text,_batch_number text,
  _expiry_date date,_stock_quantity integer,_reorder_level integer,_unit_price numeric,_barcode text DEFAULT NULL,
  _nhis_patient_price numeric DEFAULT 0,_nhis_claim_amount numeric DEFAULT 0,_category text DEFAULT NULL
)
RETURNS public.pharmacy_inventory LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE r public.pharmacy_inventory; v_uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id();
BEGIN
  IF v_uid IS NULL OR NOT (public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin') OR public.has_role(v_uid,'system_superuser') OR public.has_role(v_uid,'pharmacist') OR public.current_user_has_catalogue_create_permission('create_items')) THEN RAISE EXCEPTION 'Pharmacy inventory management permission required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before updating stock'; END IF;
  IF _item_id IS NULL THEN RAISE EXCEPTION 'Inventory item is required'; END IF;
  IF pg_catalog.length(pg_catalog.btrim(coalesce(_drug_name,''))) < 2 THEN RAISE EXCEPTION 'Drug name must contain at least two characters'; END IF;
  IF coalesce(_stock_quantity,0)<0 OR coalesce(_reorder_level,0)<0 OR coalesce(_unit_price,0)<0 OR coalesce(_nhis_patient_price,0)<0 OR coalesce(_nhis_claim_amount,0)<0 THEN RAISE EXCEPTION 'Inventory values cannot be negative'; END IF;
  IF _expiry_date IS NOT NULL AND _expiry_date < CURRENT_DATE THEN RAISE EXCEPTION 'Expiry date cannot be in the past'; END IF;
  IF coalesce(_stock_quantity,0)>0 AND (_expiry_date IS NULL OR coalesce(_unit_price,0)<=0 OR coalesce(_reorder_level,0)<=0) THEN RAISE EXCEPTION 'Expiry date, positive retail price and a configured reorder level are required before stock can be made available'; END IF;
  UPDATE public.pharmacy_inventory SET brand_name=NULLIF(pg_catalog.btrim(_brand_name),''),generic_name=NULLIF(pg_catalog.btrim(_generic_name),''),strength=NULLIF(pg_catalog.btrim(_strength),''),form=NULLIF(pg_catalog.btrim(_form),''),supplier=NULLIF(pg_catalog.btrim(_supplier),''),batch_number=NULLIF(pg_catalog.btrim(_batch_number),''),expiry_date=_expiry_date,stock_quantity=coalesce(_stock_quantity,0),reorder_level=coalesce(_reorder_level,0),unit_price=coalesce(_unit_price,0),barcode=NULLIF(pg_catalog.btrim(_barcode),''),nhis_patient_price=coalesce(_nhis_patient_price,0),nhis_claim_amount=coalesce(_nhis_claim_amount,0),updated_at=pg_catalog.now() WHERE id=_item_id AND facility_id=v_facility AND active RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active pharmacy inventory item was not found in the active facility'; END IF;
  IF r.catalogue_id IS NOT NULL AND NULLIF(pg_catalog.btrim(_category),'') IS NOT NULL THEN UPDATE public.medication_catalogue SET category=pg_catalog.btrim(_category),updated_at=pg_catalog.now() WHERE id=r.catalogue_id; END IF;
  PERFORM public.record_system_audit('pharmacy_inventory_updated','pharmacy','pharmacy_inventory',r.id,'info',pg_catalog.jsonb_build_object('drug_name',r.drug_name,'stock_quantity',r.stock_quantity,'unit_price',r.unit_price,'facility_id',v_facility,'actor_id',v_uid));
  RETURN r;
END;
$function$;
REVOKE ALL ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text) TO authenticated;
