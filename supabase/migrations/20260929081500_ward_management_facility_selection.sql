BEGIN;

CREATE OR REPLACE FUNCTION public.create_ward_unit(
  _name text,
  _code text,
  _specialty text,
  _gender_policy text,
  _facility_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
  v_name text := NULLIF(pg_catalog.btrim(_name), '');
  v_code text := NULLIF(pg_catalog.btrim(_code), '');
  v_specialty text := NULLIF(pg_catalog.btrim(_specialty), '');
  v_gender_policy text := lower(NULLIF(pg_catalog.btrim(_gender_policy), ''));
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    RAISE EXCEPTION 'Administrator or IT administrator role required';
  END IF;
  IF _facility_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.healthcare_facilities WHERE id=_facility_id AND is_active=true
  ) THEN RAISE EXCEPTION 'Active facility is required'; END IF;
  IF NOT public.has_facility_access(uid,_facility_id) THEN RAISE EXCEPTION 'Facility access required'; END IF;
  IF v_name IS NULL OR v_code IS NULL THEN RAISE EXCEPTION 'Ward name and code are required'; END IF;
  IF v_gender_policy IS NULL OR v_gender_policy NOT IN ('mixed','male','female') THEN RAISE EXCEPTION 'Invalid gender policy'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.ward_units
    WHERE lower(pg_catalog.btrim(name))=lower(v_name)
       OR lower(pg_catalog.btrim(code))=lower(v_code)
  ) THEN RAISE EXCEPTION 'Ward name or code already exists'; END IF;

  INSERT INTO public.ward_units(name,code,specialty,gender_policy,active,facility_id)
  VALUES(v_name,v_code,v_specialty,v_gender_policy,true,_facility_id)
  RETURNING id INTO v_id;
  PERFORM public.record_system_audit(
    'ward_unit_created','inpatient','ward_units',v_id,'info',
    jsonb_build_object('name',v_name,'code',v_code,'facility_id',_facility_id,'actor_id',uid)
  );
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_ward_unit(
  _name text,
  _code text,
  _specialty text DEFAULT NULL,
  _gender_policy text DEFAULT 'mixed'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
BEGIN
  RETURN public.create_ward_unit(_name,_code,_specialty,_gender_policy,public.current_user_facility_id());
END;
$function$;

REVOKE ALL ON FUNCTION public.create_ward_unit(text,text,text,text,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_ward_unit(text,text,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_ward_unit(text,text,text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_ward_unit(text,text,text,text) TO authenticated;

COMMIT;