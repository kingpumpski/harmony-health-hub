-- Align administrative workspace access, patient directory visibility and facility stock editing.
-- Zero-stock/zero-price rows remain a valid facility configuration state.

CREATE OR REPLACE FUNCTION public.get_admission_workspace(_limit integer DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_role text; v_facility uuid; v_limit integer:=greatest(1,least(coalesce(_limit,200),500));
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=auth.uid() ORDER BY ur.created_at DESC LIMIT 1;
 IF v_role IS NULL THEN RAISE EXCEPTION 'Staff profile required'; END IF;
 IF v_role NOT IN ('admin','it_admin','system_superuser','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Admission workspace access is not permitted'; END IF;
 v_facility:=public.current_user_facility_id();
 RETURN COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) ORDER BY x.admitted_at DESC) FROM (
   SELECT a.id,a.patient_id,a.admitted_at,a.discharged_at,a.ward,a.bed,a.reason,a.status,a.discharge_summary
   FROM public.admissions a JOIN public.patients p ON p.id=a.patient_id
   LEFT JOIN public.ward_beds b ON b.admission_id=a.id LEFT JOIN public.ward_units w ON w.id=b.ward_id
   WHERE p.status <> 'inactive'
   AND (v_role IN ('admin','it_admin','system_superuser') OR v_facility IS NULL OR b.facility_id IS NULL OR b.facility_id=v_facility OR w.facility_id=v_facility OR b.id IS NULL)
   ORDER BY a.admitted_at DESC LIMIT v_limit)x),'[]'::jsonb);
END $function$;
REVOKE ALL ON FUNCTION public.get_admission_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_admission_workspace(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_ward_management_workspace(_limit integer DEFAULT 500)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE uid uuid:=auth.uid(); v_role text; v_facility uuid:=public.current_user_facility_id(); v_limit integer:=greatest(1,least(coalesce(_limit,500),1000)); result jsonb;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 SELECT ur.role::text INTO v_role FROM public.user_roles ur WHERE ur.user_id=uid ORDER BY ur.created_at DESC LIMIT 1;
 IF v_role NOT IN ('admin','it_admin','system_superuser','practitioner','nurse','midwife','specialist_nurse') THEN RAISE EXCEPTION 'Not authorised'; END IF;
 SELECT pg_catalog.jsonb_build_object(
 'wards',COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x)) FROM (
   SELECT w.id,w.name,w.code,w.specialty,w.gender_policy,w.active,w.facility_id,hf.name facility_name,false is_legacy,NULL::uuid legacy_id
   FROM public.ward_units w LEFT JOIN public.healthcare_facilities hf ON hf.id=w.facility_id
   WHERE v_role IN ('admin','it_admin','system_superuser') OR w.facility_id IS NULL OR w.facility_id=v_facility
   UNION ALL
   SELECT lw.id,lw.name,lw.code,lw.department specialty,lw.gender_policy,lw.active,NULL::uuid,NULL::text,true,lw.id
   FROM public.wards lw
   WHERE NOT EXISTS (SELECT 1 FROM public.ward_units w2 WHERE lower(pg_catalog.btrim(w2.code))=lower(pg_catalog.btrim(lw.code)))
   AND v_role IN ('admin','it_admin','system_superuser')
   ORDER BY is_legacy,name LIMIT v_limit)x),'[]'::jsonb),
 'beds',COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x)) FROM (
   SELECT b.id,b.ward_id,b.bed_number,b.status,b.patient_id,b.admission_id,b.facility_id FROM public.ward_beds b
   WHERE v_role IN ('admin','it_admin','system_superuser') OR b.facility_id IS NULL OR b.facility_id=v_facility
   ORDER BY b.bed_number LIMIT v_limit)x),'[]'::jsonb),
 'facilities',CASE WHEN v_role IN ('admin','it_admin','system_superuser') THEN COALESCE((SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x)) FROM (
   SELECT id,name,facility_code,facility_type,district,region,is_active FROM public.healthcare_facilities WHERE is_active=true ORDER BY name)x),'[]'::jsonb) ELSE '[]'::jsonb END
 ) INTO result;
 RETURN result;
END;$function$;
REVOKE ALL ON FUNCTION public.get_ward_management_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ward_management_workspace(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.search_patient_directory(_query text DEFAULT NULL,_limit integer DEFAULT 300)
RETURNS TABLE(id uuid,patient_code text,first_name text,last_name text,phone text,ghana_card_number text,status text,insurance_provider text,insurance_number text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE uid uuid:=auth.uid(); active_facility uuid; is_admin boolean; is_test_user boolean; test_facility uuid; can_sensitive boolean; q text:=nullif(pg_catalog.btrim(coalesce(_query,'')),''); lim integer:=least(greatest(coalesce(_limit,100),1),1000);
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role) OR public.has_role(uid,'system_superuser'::public.app_role) OR public.has_role(uid,'practitioner'::public.app_role) OR public.has_role(uid,'nurse'::public.app_role) OR public.has_role(uid,'midwife'::public.app_role) OR public.has_role(uid,'specialist_nurse'::public.app_role) OR public.has_role(uid,'lab_technician'::public.app_role) OR public.has_role(uid,'radiologist'::public.app_role) OR public.has_role(uid,'radiology_technician'::public.app_role) OR public.has_role(uid,'pharmacist'::public.app_role) OR public.has_role(uid,'accountant'::public.app_role) OR public.has_role(uid,'front_desk'::public.app_role) OR public.has_role(uid,'canteen'::public.app_role)) THEN RAISE EXCEPTION 'Not authorized to access the staff patient directory'; END IF;
 is_admin:=public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role) OR public.has_role(uid,'system_superuser'::public.app_role);
 is_test_user:=public.hms_current_user_is_test_user(); active_facility:=public.current_user_facility_id();
 IF is_test_user THEN test_facility:=public.hms_test_facility_id(); IF test_facility IS NULL THEN RAISE EXCEPTION 'Test mode is active but TEST-0001 is not configured'; END IF; active_facility:=test_facility; is_admin:=false; END IF;
 IF NOT is_admin AND active_facility IS NULL THEN RAISE EXCEPTION 'An active facility is required to search patient records'; END IF;
 can_sensitive:=public.has_role(uid,'admin'::public.app_role) OR public.has_role(uid,'it_admin'::public.app_role) OR public.has_role(uid,'system_superuser'::public.app_role) OR public.has_role(uid,'practitioner'::public.app_role) OR public.has_role(uid,'nurse'::public.app_role) OR public.has_role(uid,'midwife'::public.app_role) OR public.has_role(uid,'specialist_nurse'::public.app_role) OR public.has_role(uid,'accountant'::public.app_role) OR public.has_role(uid,'front_desk'::public.app_role);
 RETURN QUERY SELECT p.id,p.patient_code,p.first_name,p.last_name,p.phone,CASE WHEN can_sensitive THEN p.ghana_card_number ELSE NULL END,p.status::text,CASE WHEN can_sensitive THEN p.insurance_provider ELSE NULL END,CASE WHEN can_sensitive THEN p.insurance_number ELSE NULL END
 FROM public.patients p WHERE coalesce(p.status,'active') <> 'inactive' AND (q IS NULL OR p.patient_code ILIKE '%'||q||'%' OR p.first_name ILIKE '%'||q||'%' OR p.last_name ILIKE '%'||q||'%' OR p.phone ILIKE '%'||q||'%' OR p.ghana_card_number ILIKE '%'||q||'%' OR p.email ILIKE '%'||q||'%')
 AND (is_admin OR (p.facility_id=active_facility AND public.current_user_has_facility_access(p.facility_id)))
 ORDER BY p.created_at DESC LIMIT lim;
END;$function$;
REVOKE ALL ON FUNCTION public.search_patient_directory(text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.search_patient_directory(text,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_pharmacy_inventory_item(_item_id uuid,_drug_name text,_brand_name text,_generic_name text,_strength text,_form text,_supplier text,_batch_number text,_expiry_date date,_stock_quantity integer,_reorder_level integer,_unit_price numeric,_barcode text DEFAULT NULL,_nhis_patient_price numeric DEFAULT 0,_nhis_claim_amount numeric DEFAULT 0,_category text DEFAULT NULL)
RETURNS public.pharmacy_inventory LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE r public.pharmacy_inventory; v_uid uuid:=auth.uid(); v_facility uuid:=public.current_user_facility_id();
BEGIN
 IF v_uid IS NULL OR NOT (public.has_role(v_uid,'admin') OR public.has_role(v_uid,'it_admin') OR public.has_role(v_uid,'system_superuser') OR public.has_role(v_uid,'pharmacist') OR public.current_user_has_catalogue_create_permission('create_items')) THEN RAISE EXCEPTION 'Pharmacy inventory management permission required'; END IF;
 IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before updating stock'; END IF;
 IF _item_id IS NULL THEN RAISE EXCEPTION 'Inventory item is required'; END IF;
 IF pg_catalog.length(pg_catalog.btrim(coalesce(_drug_name,'')))<2 THEN RAISE EXCEPTION 'Drug name must contain at least two characters'; END IF;
 IF coalesce(_stock_quantity,0)<0 OR coalesce(_reorder_level,0)<0 OR coalesce(_unit_price,0)<0 OR coalesce(_nhis_patient_price,0)<0 OR coalesce(_nhis_claim_amount,0)<0 THEN RAISE EXCEPTION 'Inventory values cannot be negative'; END IF;
 IF _expiry_date IS NOT NULL AND _expiry_date<CURRENT_DATE THEN RAISE EXCEPTION 'Expiry date cannot be in the past'; END IF;
 IF coalesce(_stock_quantity,0)>0 AND (_expiry_date IS NULL OR coalesce(_unit_price,0)<=0 OR coalesce(_reorder_level,0)<=0) THEN RAISE EXCEPTION 'Expiry date, positive retail price and a configured reorder level are required before stock can be made available'; END IF;
 UPDATE public.pharmacy_inventory SET brand_name=NULLIF(pg_catalog.btrim(_brand_name),''),generic_name=NULLIF(pg_catalog.btrim(_generic_name),''),strength=NULLIF(pg_catalog.btrim(_strength),''),form=NULLIF(pg_catalog.btrim(_form),''),supplier=NULLIF(pg_catalog.btrim(_supplier),''),batch_number=NULLIF(pg_catalog.btrim(_batch_number),''),expiry_date=_expiry_date,stock_quantity=coalesce(_stock_quantity,0),reorder_level=coalesce(_reorder_level,0),unit_price=coalesce(_unit_price,0),barcode=NULLIF(pg_catalog.btrim(_barcode),''),nhis_patient_price=coalesce(_nhis_patient_price,0),nhis_claim_amount=coalesce(_nhis_claim_amount,0),updated_at=pg_catalog.now()
 WHERE id=_item_id AND facility_id=v_facility AND active RETURNING * INTO r;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active pharmacy inventory item was not found in the active facility'; END IF;
 IF r.catalogue_id IS NOT NULL AND NULLIF(pg_catalog.btrim(_category),'') IS NOT NULL THEN UPDATE public.medication_catalogue SET category=pg_catalog.btrim(_category),updated_at=pg_catalog.now() WHERE id=r.catalogue_id; END IF;
 PERFORM public.record_system_audit('pharmacy_inventory_updated','pharmacy','pharmacy_inventory',r.id,'info',pg_catalog.jsonb_build_object('drug_name',r.drug_name,'stock_quantity',r.stock_quantity,'unit_price',r.unit_price,'facility_id',v_facility,'actor_id',v_uid));
 RETURN r;
END;$function$;
REVOKE ALL ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text) TO authenticated;
