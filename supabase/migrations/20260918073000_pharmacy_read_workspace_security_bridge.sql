-- Role-scoped pharmacy read workspace. Frontend reads protected pharmacy data through one audited RPC.
CREATE OR REPLACE FUNCTION public.get_pharmacy_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'front_desk')) THEN
    RAISE EXCEPTION 'Pharmacy role required';
  END IF;
  _limit := LEAST(GREATEST(COALESCE(_limit,200),1),500);
  SELECT jsonb_build_object(
    'patients', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name,p.last_name) FROM (
      SELECT id,first_name,last_name,patient_code FROM public.patients WHERE status <> 'inactive' ORDER BY first_name,last_name LIMIT _limit
    ) p),'[]'::jsonb),
    'inventory', COALESCE((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.drug_name) FROM (
      SELECT id,drug_name,brand_name,generic_name,form,strength,stock_quantity,reorder_level,unit_price,supplier,batch_number,expiry_date
      FROM public.pharmacy_inventory WHERE active ORDER BY drug_name LIMIT _limit
    ) i),'[]'::jsonb),
    'prescriptions', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (
      SELECT r.id,r.patient_id,r.medication,r.dosage,r.frequency,r.duration,r.computed_quantity,r.status,r.created_at,
             jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,'patient_code',p.patient_code) AS patients
      FROM public.prescriptions r JOIN public.patients p ON p.id=r.patient_id
      WHERE r.status IN ('pending','paid') ORDER BY r.created_at DESC LIMIT _limit
    ) x),'[]'::jsonb),
    'plans', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (
      SELECT d.id,d.medication_name,d.prepared_quantity,d.service_order_id,d.status,d.created_at,
             so.status AS service_order_status,
             jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,'patient_code',p.patient_code) AS patients
      FROM public.pharmacy_dispensing_plans d
      JOIN public.patients p ON p.id=d.patient_id
      LEFT JOIN public.service_orders so ON so.id=d.service_order_id
      WHERE d.status <> 'cancelled' ORDER BY d.created_at DESC LIMIT _limit
    ) x),'[]'::jsonb),
    'pos_sales', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC) FROM (
      SELECT s.id,s.medication,s.quantity,s.total_amount,s.status,s.service_order_id,s.created_at,
             COALESCE(so.status,s.status) AS effective_status
      FROM public.pharmacy_pos_sales s LEFT JOIN public.service_orders so ON so.id=s.service_order_id
      WHERE s.status NOT IN ('dispensed','cancelled') ORDER BY s.created_at DESC LIMIT _limit
    ) x),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_pharmacy_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_pharmacy_workspace(integer) TO authenticated;
