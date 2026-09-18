-- Role-scoped laboratory read workspace.
CREATE OR REPLACE FUNCTION public.get_laboratory_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public
AS $$
DECLARE result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'lab_technician') OR public.has_role(auth.uid(),'practitioner') OR public.has_role(auth.uid(),'nurse') OR public.has_role(auth.uid(),'midwife') OR public.has_role(auth.uid(),'specialist_nurse') OR public.has_role(auth.uid(),'radiologist')) THEN
    RAISE EXCEPTION 'Laboratory role required';
  END IF;
  _limit := LEAST(GREATEST(COALESCE(_limit,200),1),500);
  SELECT jsonb_build_object(
    'patients', COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name,p.last_name) FROM (SELECT id,first_name,last_name,patient_code,email FROM public.patients WHERE status <> 'inactive' ORDER BY first_name,last_name LIMIT _limit) p),'[]'::jsonb),
    'catalogue', COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.test_name) FROM (SELECT id,test_code,test_name,category,specimen_type,unit,reference_low,reference_high,reference_text,default_charge,active FROM public.lab_test_catalogue WHERE active ORDER BY test_name LIMIT _limit) c),'[]'::jsonb),
    'orders', COALESCE((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC) FROM (SELECT id,patient_id,test_name,test_category,priority,status,created_at,clinical_notes,lab_test_catalogue_id FROM public.lab_orders ORDER BY created_at DESC LIMIT _limit) o),'[]'::jsonb),
    'results', COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.entered_at DESC) FROM (SELECT id,lab_order_id,result_data,interpretation,is_abnormal,status,entered_at,approved_at,numeric_value,unit,reference_low,reference_high,abnormal_flag FROM public.lab_results lr ORDER BY entered_at DESC LIMIT _limit) r),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_laboratory_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_workspace(integer) TO authenticated;
