-- Route clinical lifecycle mutations through authenticated server-authoritative RPCs.
-- Read access remains governed by existing RLS policies.

REVOKE INSERT, UPDATE, DELETE ON TABLE public.lab_orders FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.lab_results FROM authenticated;
REVOKE INSERT ON TABLE public.imaging_orders FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.prescriptions FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.pharmacy_inventory FROM authenticated;

CREATE OR REPLACE FUNCTION public.create_pharmacy_inventory_item(
  _drug_name TEXT, _brand_name TEXT, _generic_name TEXT, _strength TEXT, _form TEXT,
  _supplier TEXT, _batch_number TEXT, _expiry_date DATE, _stock_quantity INTEGER,
  _reorder_level INTEGER, _unit_price NUMERIC
)
RETURNS public.pharmacy_inventory
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE result public.pharmacy_inventory;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist')) THEN
    RAISE EXCEPTION 'Pharmacy role required';
  END IF;
  IF length(trim(COALESCE(_drug_name,''))) < 2 THEN RAISE EXCEPTION 'Drug name is required'; END IF;
  IF COALESCE(_stock_quantity,0) < 0 OR COALESCE(_reorder_level,0) < 0 OR COALESCE(_unit_price,0) < 0 THEN
    RAISE EXCEPTION 'Inventory values cannot be negative';
  END IF;
  INSERT INTO public.pharmacy_inventory(drug_name,brand_name,generic_name,strength,form,supplier,batch_number,expiry_date,stock_quantity,reorder_level,unit_price)
  VALUES(trim(_drug_name),NULLIF(trim(_brand_name),''),NULLIF(trim(_generic_name),''),NULLIF(trim(_strength),''),NULLIF(trim(_form),''),NULLIF(trim(_supplier),''),NULLIF(trim(_batch_number),''),_expiry_date,COALESCE(_stock_quantity,0),COALESCE(_reorder_level,0),COALESCE(_unit_price,0))
  RETURNING * INTO result;
  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pharmacy_inventory_item(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,DATE,INTEGER,INTEGER,NUMERIC) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_inventory_item(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,DATE,INTEGER,INTEGER,NUMERIC) TO authenticated;

GRANT EXECUTE ON FUNCTION public.create_lab_order_with_payment_gate(UUID,TEXT,TEXT,TEXT,TEXT,NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_imaging_order_with_payment_gate(UUID,UUID,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_encounter_prescription(UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated;
