-- Compatibility and zero-value stock editing hardening.
-- Keeps current canonical 16-argument stock update while accepting older deployed clients.

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
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  RETURN public.update_pharmacy_inventory_item(_item_id,_drug_name,_brand_name,_generic_name,_strength,_form,_supplier,_batch_number,_expiry_date,_stock_quantity,_reorder_level,_unit_price,NULL,0,0,NULL);
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_pharmacy_inventory_item(
  _item_id uuid,_drug_name text,_brand_name text,_generic_name text,_strength text,_form text,_supplier text,_batch_number text,
  _expiry_date date,_stock_quantity integer,_reorder_level integer,_unit_price numeric,_barcode text,_nhis_patient_price numeric,_nhis_claim_amount numeric
)
RETURNS public.pharmacy_inventory
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  RETURN public.update_pharmacy_inventory_item(_item_id,_drug_name,_brand_name,_generic_name,_strength,_form,_supplier,_batch_number,_expiry_date,_stock_quantity,_reorder_level,_unit_price,_barcode,_nhis_patient_price,_nhis_claim_amount,NULL);
END;
$function$;

REVOKE ALL ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric) TO authenticated;
