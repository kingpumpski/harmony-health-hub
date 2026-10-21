BEGIN;

CREATE TABLE public.lab_test_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id uuid NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  group_name text NOT NULL CHECK (length(btrim(group_name)) BETWEEN 2 AND 120),
  group_code text NOT NULL CHECK (length(btrim(group_code)) BETWEEN 2 AND 40),
  description text,
  default_charge numeric NOT NULL DEFAULT 0 CHECK (default_charge >= 0),
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX lab_test_groups_facility_code_uidx
  ON public.lab_test_groups(facility_id, lower(group_code));

CREATE TABLE public.lab_test_group_items (
  group_id uuid NOT NULL REFERENCES public.lab_test_groups(id) ON DELETE CASCADE,
  test_id uuid NOT NULL REFERENCES public.lab_test_catalogue(id) ON DELETE RESTRICT,
  display_order integer NOT NULL CHECK (display_order >= 0),
  PRIMARY KEY (group_id, test_id),
  UNIQUE (group_id, display_order)
);

ALTER TABLE public.lab_orders
  ADD COLUMN group_id uuid REFERENCES public.lab_test_groups(id) ON DELETE SET NULL,
  ADD COLUMN parent_order_id uuid REFERENCES public.lab_orders(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX lab_orders_panel_child_test_uidx
  ON public.lab_orders(parent_order_id, lab_test_catalogue_id)
  WHERE parent_order_id IS NOT NULL;
CREATE INDEX lab_test_group_items_test_id_idx ON public.lab_test_group_items(test_id);

ALTER TABLE public.lab_test_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_test_group_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lab_test_groups, public.lab_test_group_items FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_laboratory_test_groups(_include_inactive boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  result jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility to access laboratory panels'; END IF;
  IF NOT (
    public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'lab_technician'::public.app_role) OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role) OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
  ) THEN RAISE EXCEPTION 'Laboratory panel access is not permitted'; END IF;
  IF _include_inactive AND NOT (
    public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)
    OR (public.has_role(uid,'lab_technician'::public.app_role) AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id=uid AND (p.department IS NULL OR lower(btrim(p.department)) IN ('laboratory','lab'))
    ))
  ) THEN RAISE EXCEPTION 'Laboratory panel administration access is not permitted'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(g) ORDER BY g.group_name),'[]'::jsonb)
  INTO result
  FROM (
    SELECT t.id,t.group_name,t.group_code,t.description,t.default_charge,t.is_active,
      coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'id',c.id,'test_code',c.test_code,'test_name',c.test_name,'category',c.category,
          'specimen_type',c.specimen_type,'sample_quantity',c.sample_quantity,'unit',c.unit,
          'reference_low',c.reference_low,'reference_high',c.reference_high,
          'reference_text',c.reference_text,'default_charge',c.default_charge,
          'parameters',c.parameters,'active',c.active,'display_order',i.display_order
        ) ORDER BY i.display_order)
        FROM public.lab_test_group_items i
        JOIN public.lab_test_catalogue c ON c.id=i.test_id AND (_include_inactive OR c.active)
        WHERE i.group_id=t.id
      ),'[]'::jsonb) AS tests
    FROM public.lab_test_groups t
    WHERE t.facility_id=v_facility AND (_include_inactive OR t.is_active)
      AND (_include_inactive OR NOT EXISTS (
        SELECT 1 FROM public.lab_test_group_items i
        JOIN public.lab_test_catalogue c ON c.id=i.test_id
        WHERE i.group_id=t.id AND NOT c.active
      ))
  ) g;
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_laboratory_test_group(
  _group_id uuid,
  _group_name text,
  _group_code text,
  _description text,
  _default_charge numeric,
  _test_ids uuid[],
  _is_active boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_group_id uuid;
  v_old jsonb;
  v_test_count integer;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)
    OR (public.has_role(uid,'lab_technician'::public.app_role) AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id=uid AND (p.department IS NULL OR lower(btrim(p.department)) IN ('laboratory','lab'))
    ))
  ) THEN RAISE EXCEPTION 'Laboratory panel administration access is not permitted'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before managing panels'; END IF;
  IF length(btrim(coalesce(_group_name,''))) NOT BETWEEN 2 AND 120
     OR length(btrim(coalesce(_group_code,''))) NOT BETWEEN 2 AND 40 THEN
    RAISE EXCEPTION 'Panel name and code are required';
  END IF;
  IF _default_charge IS NULL OR _default_charge < 0 THEN RAISE EXCEPTION 'Panel tariff must be non-negative'; END IF;
  IF coalesce(cardinality(_test_ids),0) < 1 THEN RAISE EXCEPTION 'Select at least one active laboratory test'; END IF;
  SELECT count(DISTINCT id) INTO v_test_count
  FROM public.lab_test_catalogue WHERE id=ANY(_test_ids) AND (NOT coalesce(_is_active,true) OR active);
  IF v_test_count <> cardinality(_test_ids) THEN RAISE EXCEPTION 'Panel contains a duplicate, missing or inactive catalogue test'; END IF;

  IF _group_id IS NOT NULL THEN
    SELECT to_jsonb(g) INTO v_old FROM public.lab_test_groups g
    WHERE g.id=_group_id AND g.facility_id=v_facility FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory panel not found in the active facility'; END IF;
    UPDATE public.lab_test_groups SET group_name=btrim(_group_name),group_code=upper(btrim(_group_code)),
      description=nullif(btrim(coalesce(_description,'')),''),default_charge=_default_charge,
      is_active=coalesce(_is_active,true),updated_at=now()
    WHERE id=_group_id RETURNING id INTO v_group_id;
    DELETE FROM public.lab_test_group_items WHERE group_id=v_group_id;
    INSERT INTO public.lab_test_group_items(group_id,test_id,display_order)
    SELECT v_group_id,test_id,ordinality::integer-1 FROM unnest(_test_ids) WITH ORDINALITY AS x(test_id,ordinality);
    PERFORM public.record_system_audit(
      CASE WHEN coalesce(_is_active,true) THEN 'lab_test_group_updated' ELSE 'lab_test_group_deactivated' END,
      'laboratory','lab_test_groups',v_group_id,'info',
      jsonb_build_object('old_value',v_old,'new_value',jsonb_build_object(
        'group_name',btrim(_group_name),'group_code',upper(btrim(_group_code)),
        'description',nullif(btrim(coalesce(_description,'')),''),'default_charge',_default_charge,
        'is_active',coalesce(_is_active,true),'test_ids',to_jsonb(_test_ids)))
    );
  ELSE
    INSERT INTO public.lab_test_groups(facility_id,group_name,group_code,description,default_charge,is_active,created_by)
    VALUES(v_facility,btrim(_group_name),upper(btrim(_group_code)),
      nullif(btrim(coalesce(_description,'')),''),_default_charge,coalesce(_is_active,true),uid)
    RETURNING id INTO v_group_id;
    INSERT INTO public.lab_test_group_items(group_id,test_id,display_order)
    SELECT v_group_id,test_id,ordinality::integer-1 FROM unnest(_test_ids) WITH ORDINALITY AS x(test_id,ordinality);
    PERFORM public.record_system_audit(
      'lab_test_group_created','laboratory','lab_test_groups',v_group_id,'info',
      jsonb_build_object('new_value',jsonb_build_object(
        'group_name',btrim(_group_name),'group_code',upper(btrim(_group_code)),
        'description',nullif(btrim(coalesce(_description,'')),''),'default_charge',_default_charge,
        'is_active',coalesce(_is_active,true),'test_ids',to_jsonb(_test_ids)))
    );
  END IF;
  RETURN v_group_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.expand_paid_laboratory_panel(_parent_order_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  parent_order public.lab_orders%ROWTYPE;
  service_order public.service_orders%ROWTYPE;
  created_count integer;
BEGIN
  SELECT * INTO parent_order FROM public.lab_orders
  WHERE id=_parent_order_id AND group_id IS NOT NULL AND parent_order_id IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN 0; END IF;
  SELECT * INTO service_order FROM public.service_orders
  WHERE related_entity_id=parent_order.id AND department='laboratory'
    AND patient_id=parent_order.patient_id AND facility_id=parent_order.facility_id
  ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND OR service_order.status NOT IN ('released','in_progress','completed') THEN RETURN 0; END IF;

  INSERT INTO public.lab_orders(
    patient_id,encounter_id,ordered_by,test_name,test_category,priority,clinical_notes,status,
    facility_id,lab_test_catalogue_id,group_id,parent_order_id
  )
  SELECT parent_order.patient_id,parent_order.encounter_id,parent_order.ordered_by,c.test_name,c.category,
    parent_order.priority,parent_order.clinical_notes,'ordered',parent_order.facility_id,c.id,
    parent_order.group_id,parent_order.id
  FROM public.lab_test_group_items i
  JOIN public.lab_test_catalogue c ON c.id=i.test_id AND c.active
  WHERE i.group_id=parent_order.group_id
  ORDER BY i.display_order
  ON CONFLICT (parent_order_id,lab_test_catalogue_id) WHERE parent_order_id IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS created_count=ROW_COUNT;

  IF created_count>0 THEN
    PERFORM public.record_system_audit(
      'lab_test_group_paid','laboratory','lab_test_groups',parent_order.group_id,'info',
      jsonb_build_object('parent_order_id',parent_order.id,'service_order_id',service_order.id,
        'created_test_orders',created_count,'actor_id',service_order.created_by)
    );
  END IF;
  RETURN created_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.expand_paid_laboratory_panel_after_release()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.department='laboratory' AND NEW.status IN ('released','in_progress','completed') THEN
    IF TG_OP='INSERT' THEN
      PERFORM public.expand_paid_laboratory_panel(NEW.related_entity_id);
    ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
      PERFORM public.expand_paid_laboratory_panel(NEW.related_entity_id);
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER expand_paid_laboratory_panel_after_release
AFTER INSERT OR UPDATE OF status ON public.service_orders
FOR EACH ROW EXECUTE FUNCTION public.expand_paid_laboratory_panel_after_release();

CREATE OR REPLACE FUNCTION public.create_encounter_lab_panel_order(
  _encounter_id uuid,_group_id uuid,_priority text DEFAULT 'routine',_clinical_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_facility uuid:=public.current_user_facility_id();
  e public.encounters%ROWTYPE;
  panel public.lab_test_groups%ROWTYPE;
  response jsonb;
  parent_id uuid;
  v_count integer;
  ordered_test_count integer;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role) OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
  ) THEN RAISE EXCEPTION 'Clinical encounter ordering access required'; END IF;
  PERFORM public.ensure_encounter_facility_attribution(_encounter_id);
  SELECT * INTO e FROM public.encounters WHERE id=_encounter_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Encounter not found'; END IF;
  IF e.status IN ('completed','cancelled') THEN RAISE EXCEPTION 'Completed or cancelled encounters are read-only'; END IF;
  IF e.practitioner_id<>uid AND NOT public.has_role(uid,'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Only the encounter clinician or an administrator may order from this encounter';
  END IF;
  SELECT * INTO panel FROM public.lab_test_groups
  WHERE id=_group_id AND facility_id=v_facility AND is_active FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active laboratory panel not found in the current facility'; END IF;
  SELECT count(*) INTO v_count FROM public.lab_test_group_items i
  JOIN public.lab_test_catalogue c ON c.id=i.test_id AND c.active WHERE i.group_id=panel.id;
  IF v_count<1 THEN RAISE EXCEPTION 'Laboratory panel has no active tests'; END IF;
  ordered_test_count:=v_count;

  response:=public.create_lab_order_with_payment_gate(
    e.patient_id,panel.group_name,'Panel',coalesce(nullif(btrim(_priority),''),'routine'),
    _clinical_notes,coalesce(panel.default_charge,0),e.id
  );
  parent_id:=nullif(response->>'lab_order_id','')::uuid;
  UPDATE public.lab_orders SET group_id=panel.id WHERE id=parent_id AND facility_id=e.facility_id;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'Panel order could not be linked to this facility'; END IF;
  PERFORM public.record_system_audit(
    'lab_test_group_ordered','laboratory','lab_test_groups',panel.id,'info',
    jsonb_build_object('parent_order_id',parent_id,'encounter_id',e.id,'patient_id',e.patient_id,
      'tariff',panel.default_charge,'actor_id',uid)
  );
  IF response->>'status' IN ('released','in_progress','completed') THEN
    PERFORM public.expand_paid_laboratory_panel(parent_id);
  END IF;
  RETURN response||jsonb_build_object('group_id',panel.id,'panel_name',panel.group_name,'test_count',ordered_test_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.collect_lab_sample(_lab_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_patient_facility uuid;
  o public.lab_orders%ROWTYPE;
  g public.service_orders%ROWTYPE;
  v_specimen_id uuid;
  v_previous_specimen_id uuid;
  v_accession text;
  v_specimen_type text;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'lab_technician'::public.app_role) OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role) OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)
  ) THEN RAISE EXCEPTION 'Laboratory clinical role required'; END IF;
  SELECT * INTO o FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  SELECT p.facility_id INTO v_patient_facility FROM public.patients p WHERE p.id=o.patient_id FOR SHARE;
  IF NOT FOUND OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Laboratory patient facility attribution is unresolved'; END IF;
  IF o.facility_id IS NULL THEN RAISE EXCEPTION 'Laboratory order facility attribution is unresolved'; END IF;
  IF v_patient_facility IS DISTINCT FROM o.facility_id THEN RAISE EXCEPTION 'Laboratory order and patient facility lineage do not match'; END IF;
  IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role))
     AND (v_facility IS NULL OR o.facility_id IS DISTINCT FROM v_facility) THEN
    RAISE EXCEPTION 'Laboratory order belongs to a different facility context';
  END IF;
  IF o.status<>'ordered' THEN RAISE EXCEPTION 'Only ordered laboratory requests can have samples collected'; END IF;
  SELECT * INTO g FROM public.service_orders
  WHERE related_entity_id=coalesce(o.parent_order_id,o.id) AND department='laboratory'
    AND patient_id=o.patient_id
  ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  IF g.id IS NOT NULL AND (g.facility_id IS NULL OR g.facility_id IS DISTINCT FROM o.facility_id) THEN
    RAISE EXCEPTION 'Laboratory payment record facility lineage is unresolved or mismatched';
  END IF;
  IF g.id IS NOT NULL AND g.status NOT IN ('released','in_progress','completed') THEN
    RAISE EXCEPTION 'Payment approval required before sample collection';
  END IF;
  IF o.parent_order_id IS NOT NULL AND g.id IS NULL THEN RAISE EXCEPTION 'Panel billing record is unavailable'; END IF;
  IF o.lab_test_catalogue_id IS NOT NULL THEN
    SELECT c.specimen_type INTO v_specimen_type FROM public.lab_test_catalogue c
    WHERE c.id=o.lab_test_catalogue_id AND c.active=true;
  END IF;
  SELECT id INTO v_previous_specimen_id FROM public.lab_specimens
  WHERE lab_order_id=o.id AND status='rejected' ORDER BY rejected_at DESC LIMIT 1;
  v_accession:='LAB-'||pg_catalog.to_char(pg_catalog.now() AT TIME ZONE 'UTC','YYYYMMDD')
    ||'-'||pg_catalog.upper(pg_catalog.left(o.id::text,8))
    ||'-'||pg_catalog.upper(pg_catalog.left(gen_random_uuid()::text,8));
  INSERT INTO public.lab_specimens(
    lab_order_id,accession_number,barcode_value,specimen_type,status,collected_by,recollection_of_id
  ) VALUES (
    o.id,v_accession,v_accession,v_specimen_type,'collected',uid,v_previous_specimen_id
  ) RETURNING id INTO v_specimen_id;
  UPDATE public.lab_orders SET status='sample_collected',collected_by=uid,
    sample_collected_at=pg_catalog.now(),updated_at=pg_catalog.now() WHERE id=o.id;
  RETURN jsonb_build_object('lab_order_id',o.id,'specimen_id',v_specimen_id,
    'accession_number',v_accession,'barcode_value',v_accession,'status','sample_collected');
END;
$function$;

CREATE OR REPLACE FUNCTION public.enter_lab_result_structured(
  _lab_order_id uuid,_parameter_results jsonb,_result_text text DEFAULT NULL,
  _interpretation text DEFAULT NULL,_is_abnormal boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_facility uuid:=public.current_user_facility_id();
  v_patient_facility uuid;
  o public.lab_orders%ROWTYPE;
  c public.lab_test_catalogue%ROWTYPE;
  rid uuid;
  required_code text;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role) OR public.has_role(uid,'lab_technician'::public.app_role)) THEN
    RAISE EXCEPTION 'Laboratory technician role required';
  END IF;
  IF jsonb_typeof(coalesce(_parameter_results,'{}'::jsonb))<>'object' THEN RAISE EXCEPTION 'Structured laboratory results must be a JSON object'; END IF;
  SELECT * INTO o FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  SELECT p.facility_id INTO v_patient_facility FROM public.patients p WHERE p.id=o.patient_id FOR SHARE;
  IF NOT FOUND OR v_patient_facility IS NULL THEN RAISE EXCEPTION 'Laboratory patient facility attribution is unresolved'; END IF;
  IF o.facility_id IS NULL THEN RAISE EXCEPTION 'Laboratory order facility attribution is unresolved'; END IF;
  IF v_patient_facility IS DISTINCT FROM o.facility_id THEN RAISE EXCEPTION 'Laboratory order and patient facility lineage do not match'; END IF;
  IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role))
     AND (v_facility IS NULL OR o.facility_id IS DISTINCT FROM v_facility) THEN
    RAISE EXCEPTION 'Laboratory order belongs to a different facility context';
  END IF;
  IF o.status<>'sample_collected' THEN RAISE EXCEPTION 'Sample must be collected before result entry'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.service_orders so WHERE so.related_entity_id=coalesce(o.parent_order_id,o.id)
      AND so.department='laboratory' AND so.patient_id=o.patient_id AND so.facility_id=o.facility_id
      AND so.status IN ('released','in_progress','completed')
  ) THEN RAISE EXCEPTION 'Billing release is required before result entry'; END IF;
  IF EXISTS(SELECT 1 FROM public.lab_results WHERE lab_order_id=o.id AND status IN ('completed','approved')) THEN
    RAISE EXCEPTION 'A completed result already exists for this laboratory order';
  END IF;
  IF o.lab_test_catalogue_id IS NOT NULL THEN
    SELECT * INTO c FROM public.lab_test_catalogue WHERE id=o.lab_test_catalogue_id;
    IF c.parameters IS NOT NULL AND jsonb_array_length(c.parameters)>0 THEN
      FOR required_code IN SELECT value->>'code' FROM jsonb_array_elements(c.parameters) value
        WHERE coalesce((value->>'required')::boolean,false)=true AND nullif(value->>'code','') IS NOT NULL
      LOOP
        IF NOT (_parameter_results ? required_code) THEN RAISE EXCEPTION 'Required laboratory parameter is missing: %',required_code; END IF;
      END LOOP;
    END IF;
  END IF;
  INSERT INTO public.lab_results(
    lab_order_id,result_data,parameter_results,interpretation,is_abnormal,entered_by,status,
    numeric_value,unit,reference_low,reference_high,abnormal_flag,patient_id,result,facility_id
  ) VALUES (
    o.id,jsonb_build_object('value',coalesce(nullif(btrim(_result_text),''),_parameter_results::text)),
    coalesce(_parameter_results,'{}'::jsonb),_interpretation,_is_abnormal,uid,'completed',
    NULL,c.unit,c.reference_low,c.reference_high,CASE WHEN _is_abnormal THEN 'abnormal' ELSE 'normal' END,
    o.patient_id,nullif(btrim(_result_text),''),o.facility_id
  ) RETURNING id INTO rid;
  UPDATE public.lab_orders SET status='completed',updated_at=now() WHERE id=o.id;
  RETURN rid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.enter_lab_result(
  _lab_order_id uuid,_result_text text,_numeric_value numeric DEFAULT NULL,
  _interpretation text DEFAULT NULL,_is_abnormal boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_facility uuid:=public.current_user_facility_id();
  v_patient_facility uuid;
  o public.lab_orders%ROWTYPE;
  c public.lab_test_catalogue%ROWTYPE;
  result_id uuid;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role) OR public.has_role(uid,'lab_technician'::public.app_role)) THEN
    RAISE EXCEPTION 'Laboratory technician role required';
  END IF;
  SELECT * INTO o FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  SELECT p.facility_id INTO v_patient_facility FROM public.patients p WHERE p.id=o.patient_id FOR SHARE;
  IF NOT FOUND OR v_patient_facility IS NULL OR o.facility_id IS NULL OR v_patient_facility IS DISTINCT FROM o.facility_id THEN
    RAISE EXCEPTION 'Laboratory order and patient facility lineage is unresolved or mismatched';
  END IF;
  IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role))
     AND (v_facility IS NULL OR o.facility_id IS DISTINCT FROM v_facility) THEN
    RAISE EXCEPTION 'Laboratory order belongs to a different facility context';
  END IF;
  IF o.status<>'sample_collected' THEN RAISE EXCEPTION 'Sample must be collected before result entry'; END IF;
  IF nullif(btrim(_result_text),'') IS NULL THEN RAISE EXCEPTION 'Result value is required'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.service_orders so WHERE so.related_entity_id=coalesce(o.parent_order_id,o.id)
      AND so.department='laboratory' AND so.patient_id=o.patient_id AND so.facility_id=o.facility_id
      AND so.status IN ('released','in_progress','completed')
  ) THEN RAISE EXCEPTION 'Billing release is required before result entry'; END IF;
  IF EXISTS(SELECT 1 FROM public.lab_results WHERE lab_order_id=o.id AND status IN ('completed','approved')) THEN
    RAISE EXCEPTION 'A completed result already exists for this laboratory order';
  END IF;
  IF o.lab_test_catalogue_id IS NOT NULL THEN
    SELECT * INTO c FROM public.lab_test_catalogue WHERE id=o.lab_test_catalogue_id;
  END IF;
  INSERT INTO public.lab_results(
    lab_order_id,patient_id,facility_id,result_data,interpretation,is_abnormal,entered_by,status,
    numeric_value,unit,reference_low,reference_high,abnormal_flag,result
  ) VALUES (
    o.id,o.patient_id,o.facility_id,jsonb_build_object('value',btrim(_result_text)),
    _interpretation,_is_abnormal,uid,'completed',_numeric_value,c.unit,c.reference_low,
    c.reference_high,CASE WHEN _is_abnormal THEN 'abnormal' ELSE 'normal' END,btrim(_result_text)
  ) RETURNING id INTO result_id;
  UPDATE public.lab_orders SET status='completed',updated_at=now() WHERE id=o.id;
  RETURN result_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.save_lab_result_draft(
  _lab_order_id uuid,_parameter_results jsonb,_result_text text DEFAULT NULL,
  _interpretation text DEFAULT NULL,_is_abnormal boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_facility uuid:=public.current_user_facility_id();
  o public.lab_orders%ROWTYPE;
  r public.lab_results%ROWTYPE;
  result_id uuid;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role) OR public.has_role(uid,'lab_technician'::public.app_role)) THEN
    RAISE EXCEPTION 'Laboratory technician role required';
  END IF;
  IF jsonb_typeof(coalesce(_parameter_results,'{}'::jsonb))<>'object' THEN RAISE EXCEPTION 'Structured laboratory results must be a JSON object'; END IF;
  SELECT * INTO o FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  IF o.facility_id IS NULL OR (NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)) AND o.facility_id IS DISTINCT FROM v_facility) THEN
    RAISE EXCEPTION 'Laboratory order facility context is invalid';
  END IF;
  IF o.status<>'sample_collected' THEN RAISE EXCEPTION 'Sample must be collected before result entry'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.service_orders so WHERE so.related_entity_id=coalesce(o.parent_order_id,o.id)
      AND so.department='laboratory' AND so.patient_id=o.patient_id AND so.facility_id=o.facility_id
      AND so.status IN ('released','in_progress','completed')
  ) THEN RAISE EXCEPTION 'Billing release is required before result entry'; END IF;
  SELECT * INTO r FROM public.lab_results WHERE lab_order_id=o.id AND status='draft'
    ORDER BY entered_at DESC LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    UPDATE public.lab_results SET
      result_data=jsonb_build_object('value',coalesce(nullif(btrim(_result_text),''),_parameter_results::text)),
      parameter_results=coalesce(_parameter_results,'{}'::jsonb),
      interpretation=nullif(btrim(_interpretation),''),is_abnormal=coalesce(_is_abnormal,false),
      result=nullif(btrim(_result_text),''),updated_at=now()
    WHERE id=r.id RETURNING id INTO result_id;
  ELSE
    INSERT INTO public.lab_results(
      lab_order_id,patient_id,facility_id,result_data,parameter_results,interpretation,
      is_abnormal,entered_by,status,result
    ) VALUES (
      o.id,o.patient_id,o.facility_id,
      jsonb_build_object('value',coalesce(nullif(btrim(_result_text),''),_parameter_results::text)),
      coalesce(_parameter_results,'{}'::jsonb),nullif(btrim(_interpretation),''),
      coalesce(_is_abnormal,false),uid,'draft',nullif(btrim(_result_text),'')
    ) RETURNING id INTO result_id;
  END IF;
  RETURN result_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.approve_lab_result(_lab_result_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid:=auth.uid();
  v_facility uuid:=public.current_user_facility_id();
  r public.lab_results%ROWTYPE;
  o public.lab_orders%ROWTYPE;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role)
    OR public.has_role(uid,'lab_technician'::public.app_role) OR public.has_role(uid,'practitioner'::public.app_role)
  ) THEN RAISE EXCEPTION 'Laboratory approval role required'; END IF;
  SELECT * INTO r FROM public.lab_results WHERE id=_lab_result_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory result not found'; END IF;
  SELECT * INTO o FROM public.lab_orders WHERE id=r.lab_order_id FOR UPDATE;
  IF NOT FOUND OR r.facility_id IS NULL OR o.facility_id IS NULL OR r.facility_id IS DISTINCT FROM o.facility_id THEN
    RAISE EXCEPTION 'Laboratory result facility mismatch: attribution is unresolved or result/order facility IDs differ';
  END IF;
  IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role))
     AND (v_facility IS NULL OR r.facility_id IS DISTINCT FROM v_facility) THEN
    RAISE EXCEPTION 'Laboratory result belongs to a different facility context';
  END IF;
  IF r.status<>'completed' OR o.status<>'completed' THEN RAISE EXCEPTION 'Only completed results can be approved'; END IF;
  UPDATE public.lab_results SET status='approved',approved_by=uid,approved_at=now(),updated_at=now()
  WHERE id=r.id AND status='completed';
  UPDATE public.lab_orders SET status='approved',updated_at=now() WHERE id=o.id AND status='completed';
  PERFORM public.record_system_audit(
    CASE WHEN o.parent_order_id IS NULL THEN 'lab_result_approved' ELSE 'lab_panel_test_approved' END,
    'laboratory',CASE WHEN o.parent_order_id IS NULL THEN 'lab_orders' ELSE 'lab_test_groups' END,
    coalesce(o.parent_order_id,o.id),'info',
    jsonb_build_object('lab_order_id',o.id,'lab_result_id',r.id,'group_id',o.group_id,'test_id',o.lab_test_catalogue_id,'actor_id',uid)
  );
  IF o.ordered_by IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.notifications WHERE recipient_user_id=o.ordered_by
      AND related_entity_id=o.id AND category='diagnostic_result'
      AND title='Laboratory result ready' AND is_read=false
  ) THEN
    INSERT INTO public.notifications(
      recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata
    ) VALUES (
      o.ordered_by,'Laboratory result ready',
      format('The %s laboratory result is approved and ready for clinical review.',o.test_name),
      CASE WHEN coalesce(r.is_abnormal,false) THEN 'critical' ELSE 'info' END,
      'diagnostic_result',
      format('/laboratory?patient=%s&order=%s&result=%s',o.patient_id,o.id,r.id),
      o.patient_id,o.id,
      jsonb_build_object('workflow','lab_result_review','lab_result_id',r.id,'lab_order_id',o.id,
        'panel_id',o.group_id,'parent_order_id',o.parent_order_id,'is_abnormal',coalesce(r.is_abnormal,false),
        'requires_acknowledgement',true)
    );
  END IF;
  RETURN jsonb_build_object('lab_result_id',r.id,'lab_order_id',o.id,'encounter_id',o.encounter_id,'status','approved');
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_laboratory_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  result jsonb;
  v_department text;
  v_facility uuid:=public.current_user_facility_id();
  v_uid uuid:=auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility to access the laboratory workspace'; END IF;
  SELECT nullif(lower(btrim(p.department)),'') INTO v_department FROM public.profiles p WHERE p.id=v_uid;
  IF NOT (
    public.has_role(v_uid,'admin'::public.app_role) OR public.has_role(v_uid,'it_admin'::public.app_role)
    OR (public.has_role(v_uid,'lab_technician'::public.app_role) AND (v_department IS NULL OR v_department='laboratory'))
    OR public.has_role(v_uid,'practitioner'::public.app_role)
    OR (public.has_role(v_uid,'nurse'::public.app_role) AND (v_department IS NULL OR v_department IN ('laboratory','clinical')))
    OR (public.has_role(v_uid,'midwife'::public.app_role) AND (v_department IS NULL OR v_department IN ('laboratory','clinical')))
    OR (public.has_role(v_uid,'specialist_nurse'::public.app_role) AND (v_department IS NULL OR v_department IN ('laboratory','clinical')))
    OR (public.has_role(v_uid,'radiologist'::public.app_role) AND (v_department IS NULL OR v_department='radiology'))
  ) THEN RAISE EXCEPTION 'Laboratory workspace access is not permitted'; END IF;
  _limit:=least(greatest(coalesce(_limit,200),1),500);

  SELECT jsonb_build_object(
    'patients',coalesce((
      SELECT jsonb_agg(to_jsonb(p) ORDER BY p.first_name,p.last_name) FROM (
        SELECT id,first_name,last_name,patient_code,email,gender,date_of_birth
        FROM public.patients WHERE coalesce(status,'active')<>'inactive' AND facility_id=v_facility
        ORDER BY first_name,last_name LIMIT _limit
      ) p
    ),'[]'::jsonb),
    'catalogue',coalesce((
      SELECT jsonb_agg(to_jsonb(c) ORDER BY c.test_name) FROM (
        SELECT id,test_code,test_name,category,specimen_type,sample_quantity,unit,reference_low,
          reference_high,reference_text,default_charge,active,parameters
        FROM public.lab_test_catalogue WHERE active ORDER BY test_name LIMIT _limit
      ) c
    ),'[]'::jsonb),
    'orders',coalesce((
      SELECT jsonb_agg(to_jsonb(o) ORDER BY o.created_at DESC) FROM (
        SELECT lo.id,lo.patient_id,lo.test_name,lo.test_category,lo.priority,lo.status,lo.created_at,
          lo.clinical_notes,lo.lab_test_catalogue_id,lo.encounter_id,lo.facility_id,
          lo.group_id,lo.parent_order_id,g.group_name AS panel_name,so.id AS service_order_id,
          so.status AS billing_status
        FROM public.lab_orders lo
        JOIN public.patients p ON p.id=lo.patient_id AND p.facility_id=v_facility
        JOIN LATERAL (
          SELECT s.id,s.status FROM public.service_orders s
          WHERE s.related_entity_id=coalesce(lo.parent_order_id,lo.id) AND s.department='laboratory'
            AND s.patient_id=lo.patient_id AND s.facility_id=lo.facility_id
            AND s.status IN ('released','in_progress','completed')
          ORDER BY s.created_at DESC LIMIT 1
        ) so ON true
        LEFT JOIN public.lab_test_groups g ON g.id=lo.group_id
        WHERE lo.facility_id=v_facility AND NOT (lo.group_id IS NOT NULL AND lo.parent_order_id IS NULL)
        ORDER BY lo.created_at DESC LIMIT _limit
      ) o
    ),'[]'::jsonb),
    'results',coalesce((
      SELECT jsonb_agg(to_jsonb(r) ORDER BY r.entered_at DESC) FROM (
        SELECT lr.id,lr.lab_order_id,lr.result_data,lr.parameter_results,lr.interpretation,
          lr.is_abnormal,lr.status,lr.entered_at,lr.approved_at,lr.approved_by,
          lr.numeric_value,lr.unit,lr.reference_low,lr.reference_high,lr.abnormal_flag,lr.patient_id
        FROM public.lab_results lr
        JOIN public.lab_orders lo ON lo.id=lr.lab_order_id AND lo.facility_id=v_facility AND lo.patient_id=lr.patient_id
        JOIN public.service_orders so ON so.related_entity_id=coalesce(lo.parent_order_id,lo.id)
          AND so.department='laboratory' AND so.patient_id=lo.patient_id
          AND so.facility_id=lo.facility_id AND so.status IN ('released','in_progress','completed')
        JOIN public.patients p ON p.id=lo.patient_id AND p.facility_id=v_facility
        WHERE lr.facility_id=v_facility
        ORDER BY lr.entered_at DESC LIMIT _limit
      ) r
    ),'[]'::jsonb)
  ) INTO result;
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_clinician_lab_results(_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid:=auth.uid();
  result jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'practitioner'::public.app_role)
    OR public.has_role(uid,'nurse'::public.app_role) OR public.has_role(uid,'midwife'::public.app_role)
    OR public.has_role(uid,'specialist_nurse'::public.app_role)) THEN RAISE EXCEPTION 'Clinical report access is not permitted'; END IF;
  _limit:=least(greatest(coalesce(_limit,100),1),300);
  SELECT coalesce(jsonb_agg(row_data ORDER BY approved_at DESC NULLS LAST),'[]'::jsonb)
  INTO result
  FROM (
    SELECT r.approved_at,jsonb_build_object(
      'id',r.id,'lab_order_id',o.id,'patient_id',o.patient_id,'encounter_id',o.encounter_id,
      'test_name',o.test_name,'test_category',o.test_category,'priority',coalesce(o.priority,'routine'),
      'clinical_notes',o.clinical_notes,'result_data',r.result_data,'parameter_results',r.parameter_results,
      'result_text',r.result_data->>'value','interpretation',r.interpretation,
      'is_abnormal',coalesce(r.is_abnormal,false),'status',r.status,'entered_at',r.entered_at,
      'approved_at',r.approved_at,'acknowledged_at',r.acknowledged_at,'acknowledged_by',r.acknowledged_by,
      'numeric_value',r.numeric_value,'unit',r.unit,'reference_low',r.reference_low,
      'reference_high',r.reference_high,'abnormal_flag',r.abnormal_flag,'prescriber_id',o.ordered_by,
      'prescriber_name',nullif(btrim(coalesce(req.first_name,'')||' '||coalesce(req.last_name,'')),''),
      'panel_name',g.group_name,'parent_order_id',o.parent_order_id,
      'panel_tests',CASE WHEN o.parent_order_id IS NULL THEN '[]'::jsonb ELSE coalesce((
        SELECT jsonb_agg(jsonb_build_object('id',sibling.id,'test_name',sibling.test_name,'status',sibling.status)
          ORDER BY gi.display_order)
        FROM public.lab_orders sibling
        LEFT JOIN public.lab_test_group_items gi
          ON gi.group_id=sibling.group_id AND gi.test_id=sibling.lab_test_catalogue_id
        WHERE sibling.parent_order_id=o.parent_order_id
      ),'[]'::jsonb) END,
      'diagnoses',coalesce((
        SELECT jsonb_agg(jsonb_build_object('id',d.id,'diagnosis',d.diagnosis,'icd_code',d.icd_code,'is_principal',d.is_principal)
          ORDER BY d.is_principal DESC,d.created_at ASC)
        FROM public.diagnoses d WHERE d.encounter_id=o.encounter_id AND d.patient_id=o.patient_id
      ),'[]'::jsonb),
      'patients',jsonb_build_object('id',p.id,'first_name',p.first_name,'last_name',p.last_name,'patient_code',p.patient_code)
    ) row_data
    FROM public.lab_results r
    JOIN public.lab_orders o ON o.id=r.lab_order_id
    JOIN public.patients p ON p.id=o.patient_id
    LEFT JOIN public.encounters e ON e.id=o.encounter_id
    LEFT JOIN public.profiles req ON req.id=o.ordered_by
    LEFT JOIN public.lab_test_groups g ON g.id=o.group_id
    WHERE r.status='approved' AND o.status='approved'
      AND ((coalesce(o.facility_id,e.facility_id,p.facility_id) IS NOT NULL
        AND public.current_user_has_facility_access(coalesce(o.facility_id,e.facility_id,p.facility_id)))
        OR (coalesce(o.facility_id,e.facility_id,p.facility_id) IS NULL
          AND (o.ordered_by=uid OR e.practitioner_id=uid)))
    ORDER BY r.approved_at DESC NULLS LAST LIMIT _limit
  ) q;
  RETURN result;
END;
$function$;

DROP POLICY IF EXISTS lab_result_attachments_technician_insert ON public.lab_result_attachments;
CREATE POLICY lab_result_attachments_technician_insert
  ON public.lab_result_attachments FOR INSERT TO authenticated
  WITH CHECK (
    facility_id=(SELECT public.current_user_facility_id())
    AND uploaded_by=auth.uid()
    AND (
      (SELECT public.current_user_has_role('admin'::public.app_role))
      OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
      OR (SELECT public.current_user_has_role('lab_technician'::public.app_role))
    )
    AND EXISTS (
      SELECT 1 FROM public.lab_orders lo
      JOIN public.service_orders so ON so.related_entity_id=coalesce(lo.parent_order_id,lo.id)
        AND so.department='laboratory' AND so.patient_id=lo.patient_id
        AND so.facility_id=lo.facility_id AND so.status IN ('released','in_progress','completed')
      WHERE lo.id=lab_result_attachments.lab_order_id
        AND lo.facility_id=lab_result_attachments.facility_id
    )
  );

DROP POLICY IF EXISTS lab_result_attachments_storage_insert ON storage.objects;
CREATE POLICY lab_result_attachments_storage_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id='lab-result-attachments'
    AND (
      (SELECT public.current_user_has_role('admin'::public.app_role))
      OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
      OR (SELECT public.current_user_has_role('lab_technician'::public.app_role))
    )
    AND EXISTS (
      SELECT 1 FROM public.lab_orders lo
      JOIN public.service_orders so ON so.related_entity_id=coalesce(lo.parent_order_id,lo.id)
        AND so.department='laboratory' AND so.patient_id=lo.patient_id
        AND so.facility_id=lo.facility_id AND so.status IN ('released','in_progress','completed')
      WHERE lo.id::text=split_part(name,'/',1)
        AND lo.facility_id=(SELECT public.current_user_facility_id())
    )
  );

REVOKE ALL ON FUNCTION public.get_laboratory_test_groups(boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_test_groups(boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.save_laboratory_test_group(uuid,text,text,text,numeric,uuid[],boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_laboratory_test_group(uuid,text,text,text,numeric,uuid[],boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.expand_paid_laboratory_panel(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.expand_paid_laboratory_panel_after_release() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.create_encounter_lab_panel_order(uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_encounter_lab_panel_order(uuid,uuid,text,text) TO authenticated;
REVOKE ALL ON FUNCTION public.collect_lab_sample(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.collect_lab_sample(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.enter_lab_result_structured(uuid,jsonb,text,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enter_lab_result_structured(uuid,jsonb,text,text,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.enter_lab_result(uuid,text,numeric,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.enter_lab_result(uuid,text,numeric,text,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.save_lab_result_draft(uuid,jsonb,text,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_lab_result_draft(uuid,jsonb,text,text,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.approve_lab_result(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.approve_lab_result(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.get_laboratory_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_workspace(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.get_clinician_lab_results(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_clinician_lab_results(integer) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;
