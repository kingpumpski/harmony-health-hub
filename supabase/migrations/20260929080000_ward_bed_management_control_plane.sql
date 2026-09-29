BEGIN;

-- Ward/bed configuration belongs to the system control plane. Clinical staff
-- continue to operate beds through assignment/release workflows, but creation
-- and structural configuration are restricted to Admin and IT Admin.
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
DECLARE
  uid uuid := auth.uid();
  v_facility_id uuid := public.current_user_facility_id();
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
  IF v_facility_id IS NULL THEN
    RAISE EXCEPTION 'Active facility context required';
  END IF;
  IF NOT public.has_facility_access(uid, v_facility_id) THEN
    RAISE EXCEPTION 'Facility access required';
  END IF;
  IF v_name IS NULL OR v_code IS NULL THEN
    RAISE EXCEPTION 'Ward name and code are required';
  END IF;
  IF v_gender_policy IS NULL OR v_gender_policy NOT IN ('mixed','male','female') THEN
    RAISE EXCEPTION 'Invalid gender policy';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.ward_units
    WHERE lower(pg_catalog.btrim(name)) = lower(v_name)
       OR lower(pg_catalog.btrim(code)) = lower(v_code)
  ) THEN
    RAISE EXCEPTION 'Ward name or code already exists';
  END IF;

  INSERT INTO public.ward_units(name,code,specialty,gender_policy,active,facility_id)
  VALUES (v_name,v_code,v_specialty,v_gender_policy,true,v_facility_id)
  RETURNING id INTO v_id;

  PERFORM public.record_system_audit(
    'ward_unit_created','inpatient','ward_units',v_id,'info',
    jsonb_build_object('name',v_name,'code',v_code,'facility_id',v_facility_id,'actor_id',uid)
  );
  RETURN v_id;
END;
$function$;

-- Allow a global Admin/IT Admin to attach legacy unscoped wards to a facility.
CREATE OR REPLACE FUNCTION public.assign_ward_unit_facility(
  _ward_id uuid,
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
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    RAISE EXCEPTION 'Administrator or IT administrator role required';
  END IF;
  IF _ward_id IS NULL OR _facility_id IS NULL THEN
    RAISE EXCEPTION 'Ward and facility are required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.healthcare_facilities WHERE id=_facility_id AND is_active=true) THEN
    RAISE EXCEPTION 'Active facility not found';
  END IF;
  IF NOT public.has_facility_access(uid,_facility_id) THEN
    RAISE EXCEPTION 'Facility access required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ward_units WHERE id=_ward_id) THEN
    RAISE EXCEPTION 'Ward not found';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.ward_beds b
    WHERE b.ward_id=_ward_id AND b.facility_id IS NOT NULL AND b.facility_id<>_facility_id
  ) THEN
    RAISE EXCEPTION 'Ward has beds assigned to another facility';
  END IF;

  UPDATE public.ward_units
  SET facility_id=_facility_id, updated_at=now()
  WHERE id=_ward_id
  RETURNING id INTO v_id;

  UPDATE public.ward_beds
  SET facility_id=_facility_id, updated_at=now()
  WHERE ward_id=_ward_id AND facility_id IS NULL;

  PERFORM public.record_system_audit(
    'ward_unit_facility_assigned','inpatient','ward_units',v_id,'info',
    jsonb_build_object('facility_id',_facility_id,'actor_id',uid)
  );
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_ward_unit(
  _ward_id uuid,
  _name text,
  _code text,
  _specialty text DEFAULT NULL,
  _gender_policy text DEFAULT 'mixed',
  _active boolean DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility_id uuid;
  v_name text := NULLIF(pg_catalog.btrim(_name), '');
  v_code text := NULLIF(pg_catalog.btrim(_code), '');
  v_specialty text := NULLIF(pg_catalog.btrim(_specialty), '');
  v_gender_policy text := lower(NULLIF(pg_catalog.btrim(_gender_policy), ''));
  v_id uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    RAISE EXCEPTION 'Administrator or IT administrator role required';
  END IF;
  SELECT facility_id INTO v_facility_id FROM public.ward_units WHERE id=_ward_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ward not found'; END IF;
  IF v_facility_id IS NOT NULL AND NOT public.has_facility_access(uid,v_facility_id) THEN
    RAISE EXCEPTION 'Facility access required';
  END IF;
  IF v_name IS NULL OR v_code IS NULL THEN RAISE EXCEPTION 'Ward name and code are required'; END IF;
  IF v_gender_policy IS NULL OR v_gender_policy NOT IN ('mixed','male','female') THEN
    RAISE EXCEPTION 'Invalid gender policy';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.ward_units
    WHERE id<>_ward_id
      AND (lower(pg_catalog.btrim(name))=lower(v_name) OR lower(pg_catalog.btrim(code))=lower(v_code))
  ) THEN RAISE EXCEPTION 'Ward name or code already exists'; END IF;
  IF v_facility_id IS NULL THEN
    v_facility_id := public.current_user_facility_id();
  END IF;
  IF v_facility_id IS NULL THEN RAISE EXCEPTION 'Facility assignment required before updating legacy ward'; END IF;
  IF NOT public.has_facility_access(uid,v_facility_id) THEN RAISE EXCEPTION 'Facility access required'; END IF;

  UPDATE public.ward_units
  SET name=v_name,code=v_code,specialty=v_specialty,gender_policy=v_gender_policy,
      active=COALESCE(_active,active),facility_id=v_facility_id,updated_at=now()
  WHERE id=_ward_id
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_ward_bed(
  _ward_id uuid,
  _bed_number text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
  v_facility_id uuid;
  v_bed_number text := NULLIF(pg_catalog.btrim(_bed_number), '');
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    RAISE EXCEPTION 'Administrator or IT administrator role required';
  END IF;
  IF _ward_id IS NULL OR v_bed_number IS NULL THEN
    RAISE EXCEPTION 'Ward and bed number are required';
  END IF;

  SELECT facility_id INTO v_facility_id
  FROM public.ward_units
  WHERE id=_ward_id AND active=true
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active ward not found'; END IF;
  IF v_facility_id IS NULL THEN RAISE EXCEPTION 'Assign the ward to a facility before creating beds'; END IF;
  IF NOT public.has_facility_access(uid,v_facility_id) THEN RAISE EXCEPTION 'Facility access required'; END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(_ward_id::text,0));
  IF EXISTS (
    SELECT 1 FROM public.ward_beds
    WHERE ward_id=_ward_id
      AND lower(pg_catalog.btrim(bed_number))=lower(v_bed_number)
  ) THEN RAISE EXCEPTION 'Bed number already exists in this ward'; END IF;

  INSERT INTO public.ward_beds(ward_id,bed_number,status,facility_id)
  VALUES (_ward_id,v_bed_number,'available',v_facility_id)
  RETURNING id INTO v_id;

  PERFORM public.record_system_audit(
    'ward_bed_created','inpatient','ward_beds',v_id,'info',
    jsonb_build_object('ward_id',_ward_id,'bed_number',v_bed_number,'facility_id',v_facility_id,'actor_id',uid)
  );
  RETURN v_id;
END;
$function$;

-- Bring legacy wards created through the obsolete public.wards path into the
-- canonical ward_units read model. They remain unscoped until an Admin/IT
-- Admin assigns their facility in the Ward Management UI.
INSERT INTO public.ward_units(name,code,specialty,gender_policy,active,facility_id)
SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM public.ward_units wu WHERE lower(pg_catalog.btrim(wu.name))=lower(pg_catalog.btrim(w.name))
  ) THEN pg_catalog.btrim(w.name)||' ['||w.code||']' ELSE pg_catalog.btrim(w.name) END,
  pg_catalog.btrim(w.code),
  NULLIF(pg_catalog.btrim(w.department),''),
  CASE WHEN lower(coalesce(w.gender_policy,'mixed')) IN ('male','female') THEN lower(w.gender_policy) ELSE 'mixed' END,
  coalesce(w.active,true),
  NULL
FROM public.wards w
WHERE NOT EXISTS (
  SELECT 1 FROM public.ward_units wu WHERE lower(pg_catalog.btrim(wu.code))=lower(pg_catalog.btrim(w.code))
);

REVOKE ALL ON FUNCTION public.create_ward_unit(text,text,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.update_ward_unit(uuid,text,text,text,text,boolean) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.assign_ward_unit_facility(uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.create_ward_bed(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_ward_unit(text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_ward_unit(uuid,text,text,text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assign_ward_unit_facility(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_ward_bed(uuid,text) TO authenticated;

COMMIT;