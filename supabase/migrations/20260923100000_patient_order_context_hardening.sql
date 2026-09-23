-- Harden patient-scoped clinical order workflows.
-- Do not trust a client-supplied encounter relationship: when an encounter is supplied,
-- it must belong to the same patient as the order. Inactive patients cannot receive new orders.

CREATE OR REPLACE FUNCTION public.create_imaging_order_with_payment_gate(
  _patient_id uuid,
  _encounter_id uuid DEFAULT NULL::uuid,
  _modality text DEFAULT 'X-Ray'::text,
  _study_name text DEFAULT 'General study'::text,
  _body_site text DEFAULT NULL::text,
  _priority text DEFAULT 'routine'::text,
  _clinical_indication text DEFAULT NULL::text,
  _amount numeric DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_imaging_id uuid;
  v_service_id uuid;
  v_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(v_uid,'admin') OR public.has_role(v_uid,'practitioner') OR
    public.has_role(v_uid,'nurse') OR public.has_role(v_uid,'midwife') OR
    public.has_role(v_uid,'front_desk')
  ) THEN RAISE EXCEPTION 'Imaging order access required'; END IF;
  IF _patient_id IS NULL OR NULLIF(trim(_study_name),'') IS NULL THEN
    RAISE EXCEPTION 'Patient and study name are required';
  END IF;
  IF COALESCE(_amount,0) < 0 THEN RAISE EXCEPTION 'Amount cannot be negative'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = _patient_id AND COALESCE(status,'active') <> 'inactive'
  ) THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
  IF _encounter_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.encounters WHERE id = _encounter_id AND patient_id = _patient_id
  ) THEN
    RAISE EXCEPTION 'Encounter does not belong to patient';
  END IF;
  INSERT INTO public.imaging_orders(patient_id,encounter_id,modality,study_name,body_site,priority,clinical_indication,amount,status,requested_by)
  VALUES(_patient_id,_encounter_id,trim(_modality),trim(_study_name),NULLIF(trim(_body_site),''),COALESCE(NULLIF(trim(_priority),''),'routine'),NULLIF(trim(_clinical_indication),''),COALESCE(_amount,0),CASE WHEN COALESCE(_amount,0)>0 THEN 'pending_payment_approval' ELSE 'released' END,v_uid)
  RETURNING id,status INTO v_imaging_id,v_status;
  IF COALESCE(_amount,0)>0 THEN
    INSERT INTO public.service_orders(patient_id,encounter_id,department,service_name,amount,status,requested_by,related_entity_id,order_type,service_code,payment_required,created_by,notes)
    VALUES(_patient_id,_encounter_id,'imaging',trim(_study_name),COALESCE(_amount,0),'pending_payment_approval',v_uid,v_imaging_id,'imaging',upper(trim(_modality)),true,v_uid,NULLIF(trim(_clinical_indication),''))
    RETURNING id INTO v_service_id;
    UPDATE public.imaging_orders SET service_order_id=v_service_id WHERE id=v_imaging_id;
  END IF;
  RETURN jsonb_build_object('imaging_order_id',v_imaging_id,'service_order_id',v_service_id,'status',v_status);
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_lab_order_with_payment_gate(
  _patient_id uuid,
  _test_name text,
  _test_category text DEFAULT NULL::text,
  _priority text DEFAULT 'routine'::text,
  _clinical_notes text DEFAULT NULL::text,
  _amount numeric DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_lab_order_id uuid;
  v_service_order_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication is required'; END IF;
  IF NOT (
    public.has_role(v_uid,'admin') OR public.has_role(v_uid,'practitioner') OR
    public.has_role(v_uid,'nurse') OR public.has_role(v_uid,'midwife') OR
    public.has_role(v_uid,'lab_technician') OR public.has_role(v_uid,'front_desk')
  ) THEN RAISE EXCEPTION 'Laboratory order access required'; END IF;
  IF _patient_id IS NULL OR NULLIF(btrim(_test_name),'') IS NULL THEN
    RAISE EXCEPTION 'Patient and test name are required';
  END IF;
  IF COALESCE(_amount,0) < 0 THEN RAISE EXCEPTION 'Amount cannot be negative'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = _patient_id AND COALESCE(status,'active') <> 'inactive'
  ) THEN RAISE EXCEPTION 'Patient not found or inactive'; END IF;
  INSERT INTO public.lab_orders(patient_id,test_name,test_category,priority,status,clinical_notes,ordered_by)
  VALUES(_patient_id,btrim(_test_name),NULLIF(btrim(_test_category),''),COALESCE(NULLIF(btrim(_priority),''),'routine'),'ordered',NULLIF(btrim(_clinical_notes),''),v_uid)
  RETURNING id INTO v_lab_order_id;
  INSERT INTO public.service_orders(patient_id,department,service_name,amount,unit_price,payment_required,status,requested_by,created_by,related_entity_id,order_type,service_code,notes)
  VALUES(_patient_id,'laboratory',btrim(_test_name),COALESCE(_amount,0),COALESCE(_amount,0),COALESCE(_amount,0)>0,'pending_payment_approval',v_uid,v_uid,v_lab_order_id,'lab',NULLIF(btrim(_test_category),''),NULLIF(btrim(_clinical_notes),''))
  RETURNING id INTO v_service_order_id;
  RETURN jsonb_build_object('lab_order_id',v_lab_order_id,'service_order_id',v_service_order_id,'status','pending_payment_approval');
END;
$function$;

REVOKE ALL ON FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_imaging_order_with_payment_gate(uuid,uuid,text,text,text,text,text,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_lab_order_with_payment_gate(uuid,text,text,text,text,numeric) TO authenticated;

NOTIFY pgrst, 'reload schema';
