-- Forward-only clinical workspace read hardening and missing imaging workspace bridge.
-- Keeps existing RPC signatures and frontend contracts.

CREATE OR REPLACE FUNCTION public.get_laboratory_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public
AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'lab_technician') OR
    public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR
    public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR
    public.has_role(auth.uid(),'radiologist')
  ) THEN RAISE EXCEPTION 'Laboratory role required'; END IF;
  _limit := LEAST(GREATEST(COALESCE(_limit,200),1),500);
  SELECT jsonb_build_object(
    'patients', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name,p.last_name)
      FROM (SELECT id,first_name,last_name,patient_code FROM public.patients
            WHERE status <> 'inactive' ORDER BY first_name,last_name LIMIT _limit) p),'[]'::jsonb),
    'catalogue', COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.test_name)
      FROM (SELECT id,test_code,test_name,category,specimen_type,unit,reference_low,reference_high,reference_text,default_charge,active
            FROM public.lab_test_catalogue WHERE active ORDER BY test_name LIMIT _limit) c),'[]'::jsonb),
    'orders', COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC)
      FROM (SELECT id,patient_id,test_name,test_category,priority,status,created_at,clinical_notes,lab_test_catalogue_id
            FROM public.lab_orders ORDER BY created_at DESC LIMIT _limit) o),'[]'::jsonb),
    'results', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.entered_at DESC)
      FROM (SELECT id,lab_order_id,result_data,interpretation,is_abnormal,status,entered_at,approved_at,numeric_value,unit,reference_low,reference_high,abnormal_flag
            FROM public.lab_results ORDER BY entered_at DESC LIMIT _limit) r),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.get_laboratory_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_workspace(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pharmacy_workspace(_limit integer DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public
AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'pharmacist') OR public.has_role(auth.uid(),'front_desk')
  ) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
  _limit := LEAST(GREATEST(COALESCE(_limit,200),1),500);
  SELECT jsonb_build_object(
    'patients', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name,p.last_name)
      FROM (SELECT id,first_name,last_name,patient_code FROM public.patients WHERE status <> 'inactive'
            ORDER BY first_name,last_name LIMIT _limit) p),'[]'::jsonb),
    'inventory', COALESCE((SELECT jsonb_agg(to_jsonb(i) ORDER BY i.drug_name)
      FROM (SELECT id,drug_name,brand_name,generic_name,form,strength,stock_quantity,reorder_level,unit_price,supplier,batch_number,expiry_date
            FROM public.pharmacy_inventory WHERE active ORDER BY drug_name LIMIT _limit) i),'[]'::jsonb),
    'prescriptions', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (SELECT r.id,r.patient_id,r.medication,r.dosage,r.frequency,r.duration,r.computed_quantity,r.status,r.created_at,
                   jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,'patient_code',p.patient_code) patients
            FROM public.prescriptions r JOIN public.patients p ON p.id=r.patient_id
            WHERE r.status IN ('pending','paid') ORDER BY r.created_at DESC LIMIT _limit) x),'[]'::jsonb),
    'plans', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (SELECT d.id,d.patient_id,d.medication_name,d.prepared_quantity,d.service_order_id,d.status,d.created_at,so.status service_order_status,
                   jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,'patient_code',p.patient_code) patients
            FROM public.pharmacy_dispensing_plans d JOIN public.patients p ON p.id=d.patient_id
            LEFT JOIN public.service_orders so ON so.id=d.service_order_id
            WHERE d.status <> 'cancelled' ORDER BY d.created_at DESC LIMIT _limit) x),'[]'::jsonb),
    'pos_sales', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (SELECT s.id,s.patient_id,s.medication,s.quantity,s.total_amount,s.status,s.service_order_id,s.created_at,
                   COALESCE(so.status,s.status) effective_status
            FROM public.pharmacy_pos_sales s LEFT JOIN public.service_orders so ON so.id=s.service_order_id
            WHERE s.status NOT IN ('dispensed','cancelled') ORDER BY s.created_at DESC LIMIT _limit) x),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.get_pharmacy_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_pharmacy_workspace(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_imaging_workspace(_limit integer DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public
AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'radiologist') OR
    public.has_role(auth.uid(),'radiology_technician') OR public.has_role(auth.uid(),'practitioner')
  ) THEN RAISE EXCEPTION 'Imaging role required'; END IF;
  _limit := LEAST(GREATEST(COALESCE(_limit,200),1),500);
  SELECT jsonb_build_object(
    'patients', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name,p.last_name)
      FROM (SELECT id,first_name,last_name,patient_code FROM public.patients WHERE status <> 'inactive'
            ORDER BY first_name,last_name LIMIT _limit) p),'[]'::jsonb),
    'orders', COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (SELECT io.id,io.patient_id,io.encounter_id,io.modality,io.study_name,io.body_site,io.priority,
                   io.clinical_indication,io.amount,io.status,io.service_order_id,io.requested_by,io.performed_by,
                   io.report,io.impression,io.created_at,io.updated_at,
                   jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,'patient_code',p.patient_code) patient
            FROM public.imaging_orders io JOIN public.patients p ON p.id=io.patient_id
            WHERE io.status <> 'cancelled' ORDER BY io.created_at DESC LIMIT _limit) x),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END; $$;
REVOKE ALL ON FUNCTION public.get_imaging_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_imaging_workspace(integer) TO authenticated;
