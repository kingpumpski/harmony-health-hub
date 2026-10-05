-- Reconcile inpatient workspace authorization and facility boundaries.
CREATE OR REPLACE FUNCTION public.get_ward_management_workspace(_limit integer DEFAULT 500)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_role text;
  v_facility uuid := public.current_user_facility_id();
  v_limit integer := greatest(1,least(coalesce(_limit,500),1000));
  result jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  SELECT CASE
    WHEN public.has_role(uid,'system_superuser'::public.app_role) THEN 'system_superuser'
    WHEN public.has_role(uid,'admin'::public.app_role) THEN 'admin'
    WHEN public.has_role(uid,'it_admin'::public.app_role) THEN 'it_admin'
    WHEN public.has_role(uid,'practitioner'::public.app_role) THEN 'practitioner'
    WHEN public.has_role(uid,'nurse'::public.app_role) THEN 'nurse'
    WHEN public.has_role(uid,'midwife'::public.app_role) THEN 'midwife'
    WHEN public.has_role(uid,'specialist_nurse'::public.app_role) THEN 'specialist_nurse'
    ELSE NULL
  END INTO v_role;

  IF v_role IS NULL OR v_role NOT IN ('admin','it_admin','system_superuser','practitioner','nurse','midwife','specialist_nurse') THEN
    RAISE EXCEPTION 'Not authorised';
  END IF;

  IF v_role <> 'system_superuser' AND v_facility IS NULL THEN
    RAISE EXCEPTION 'An active facility is required for ward workspace access';
  END IF;

  SELECT pg_catalog.jsonb_build_object(
    'wards',COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x))
      FROM (
        SELECT w.id,w.name,w.code,w.specialty,w.gender_policy,w.active,w.facility_id,
               hf.name AS facility_name,false AS is_legacy,NULL::uuid AS legacy_id
        FROM public.ward_units w
        LEFT JOIN public.healthcare_facilities hf ON hf.id=w.facility_id
        WHERE (
          v_role='system_superuser'
          OR w.facility_id IS NULL
          OR w.facility_id=v_facility
        )
        UNION ALL
        SELECT lw.id,lw.name,lw.code,lw.department AS specialty,lw.gender_policy,
               lw.active,NULL::uuid,NULL::text,true,lw.id
        FROM public.wards lw
        WHERE NOT EXISTS (
          SELECT 1 FROM public.ward_units w2
          WHERE lower(pg_catalog.btrim(w2.code))=lower(pg_catalog.btrim(lw.code))
        )
        AND v_role IN ('admin','it_admin','system_superuser')
        ORDER BY is_legacy,name
        LIMIT v_limit
      ) x
    ),'[]'::jsonb),
    'beds',COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x))
      FROM (
        SELECT b.id,b.ward_id,b.bed_number,b.status,b.patient_id,b.admission_id,b.facility_id
        FROM public.ward_beds b
        WHERE (
          v_role='system_superuser'
          OR b.facility_id IS NULL
          OR b.facility_id=v_facility
        )
        ORDER BY b.bed_number
        LIMIT v_limit
      ) x
    ),'[]'::jsonb),
    'facilities',CASE
      WHEN v_role='system_superuser' THEN COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x))
        FROM (
          SELECT id,name,facility_code,facility_type,district,region,is_active
          FROM public.healthcare_facilities WHERE is_active=true ORDER BY name
        ) x
      ),'[]'::jsonb)
      WHEN v_role IN ('admin','it_admin') THEN COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x))
        FROM (
          SELECT id,name,facility_code,facility_type,district,region,is_active
          FROM public.healthcare_facilities WHERE id=v_facility AND is_active=true
        ) x
      ),'[]'::jsonb)
      ELSE '[]'::jsonb
    END
  ) INTO result;

  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_admission_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_role text;
  v_facility uuid := public.current_user_facility_id();
  v_limit integer := greatest(1,least(coalesce(_limit,200),500));
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  SELECT CASE
    WHEN public.has_role(auth.uid(),'system_superuser'::public.app_role) THEN 'system_superuser'
    WHEN public.has_role(auth.uid(),'admin'::public.app_role) THEN 'admin'
    WHEN public.has_role(auth.uid(),'it_admin'::public.app_role) THEN 'it_admin'
    WHEN public.has_role(auth.uid(),'practitioner'::public.app_role) THEN 'practitioner'
    WHEN public.has_role(auth.uid(),'nurse'::public.app_role) THEN 'nurse'
    WHEN public.has_role(auth.uid(),'midwife'::public.app_role) THEN 'midwife'
    WHEN public.has_role(auth.uid(),'specialist_nurse'::public.app_role) THEN 'specialist_nurse'
    ELSE NULL
  END INTO v_role;

  IF v_role IS NULL OR v_role NOT IN ('admin','it_admin','system_superuser','practitioner','nurse','midwife','specialist_nurse') THEN
    RAISE EXCEPTION 'Admission workspace access is not permitted';
  END IF;
  IF v_role <> 'system_superuser' AND v_facility IS NULL THEN
    RAISE EXCEPTION 'An active facility is required for admission workspace access';
  END IF;

  RETURN COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) ORDER BY x.admitted_at DESC)
    FROM (
      SELECT a.id,a.patient_id,a.admitted_at,a.discharged_at,a.ward,a.bed,
             a.reason,a.status,a.discharge_summary
      FROM public.admissions a
      JOIN public.patients p ON p.id=a.patient_id
      LEFT JOIN public.ward_beds b ON b.admission_id=a.id
      LEFT JOIN public.ward_units w ON w.id=b.ward_id
      WHERE p.status <> 'inactive'
        AND (
          v_role='system_superuser'
          OR COALESCE(a.facility_id,b.facility_id,w.facility_id,p.facility_id)=v_facility
        )
      ORDER BY a.admitted_at DESC
      LIMIT v_limit
    ) x
  ),'[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.import_legacy_ward(_legacy_ward_id uuid,_facility_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE uid uuid:=auth.uid(); legacy public.wards%ROWTYPE; v_name text; v_id uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'system_superuser')) THEN
    RAISE EXCEPTION 'Administrator, IT administrator or System Superuser role required';
  END IF;
  IF _facility_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.healthcare_facilities WHERE id=_facility_id AND is_active=true) THEN RAISE EXCEPTION 'Active facility is required'; END IF;
  IF NOT public.has_role(uid,'system_superuser') AND NOT public.has_facility_access(uid,_facility_id) THEN RAISE EXCEPTION 'Facility access required'; END IF;
  SELECT * INTO legacy FROM public.wards WHERE id=_legacy_ward_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Legacy ward not found'; END IF;
  IF EXISTS(SELECT 1 FROM public.ward_units WHERE lower(pg_catalog.btrim(code))=lower(pg_catalog.btrim(legacy.code))) THEN
    SELECT id INTO v_id FROM public.ward_units WHERE lower(pg_catalog.btrim(code))=lower(pg_catalog.btrim(legacy.code)) LIMIT 1; RETURN v_id;
  END IF;
  v_name:=NULLIF(pg_catalog.btrim(legacy.name),'');
  IF v_name IS NULL THEN RAISE EXCEPTION 'Legacy ward name is required'; END IF;
  IF EXISTS(SELECT 1 FROM public.ward_units WHERE lower(pg_catalog.btrim(name))=lower(v_name)) THEN v_name:=v_name||' ['||pg_catalog.btrim(legacy.code)||']'; END IF;
  INSERT INTO public.ward_units(name,code,specialty,gender_policy,active,facility_id)
  VALUES(v_name,pg_catalog.btrim(legacy.code),NULLIF(pg_catalog.btrim(legacy.department),''),
    CASE WHEN lower(coalesce(legacy.gender_policy,'mixed')) IN('male','female') THEN lower(legacy.gender_policy) ELSE 'mixed' END,
    coalesce(legacy.active,true),_facility_id) RETURNING id INTO v_id;
  PERFORM public.record_system_audit('legacy_ward_imported','inpatient','ward_units',v_id,'info',
    pg_catalog.jsonb_build_object('legacy_ward_id',_legacy_ward_id,'facility_id',_facility_id,'actor_id',uid));
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.assign_ward_unit_facility(_ward_id uuid,_facility_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE uid uuid:=auth.uid(); v_id uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'system_superuser')) THEN
    RAISE EXCEPTION 'Administrator, IT administrator or System Superuser role required';
  END IF;
  IF _ward_id IS NULL OR _facility_id IS NULL THEN RAISE EXCEPTION 'Ward and facility are required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.healthcare_facilities WHERE id=_facility_id AND is_active=true) THEN RAISE EXCEPTION 'Active facility not found'; END IF;
  IF NOT public.has_role(uid,'system_superuser') AND NOT public.has_facility_access(uid,_facility_id) THEN RAISE EXCEPTION 'Facility access required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.ward_units WHERE id=_ward_id) THEN RAISE EXCEPTION 'Ward not found'; END IF;
  IF EXISTS(SELECT 1 FROM public.ward_beds b WHERE b.ward_id=_ward_id AND b.facility_id IS NOT NULL AND b.facility_id<>_facility_id) THEN RAISE EXCEPTION 'Ward has beds assigned to another facility'; END IF;
  UPDATE public.ward_units SET facility_id=_facility_id,updated_at=pg_catalog.now() WHERE id=_ward_id RETURNING id INTO v_id;
  UPDATE public.ward_beds SET facility_id=_facility_id,updated_at=pg_catalog.now() WHERE ward_id=_ward_id AND facility_id IS NULL;
  PERFORM public.record_system_audit('ward_unit_facility_assigned','inpatient','ward_units',v_id,'info',
    pg_catalog.jsonb_build_object('facility_id',_facility_id,'actor_id',uid));
  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_ward_management_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ward_management_workspace(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.get_admission_workspace(integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_admission_workspace(integer) TO authenticated;
REVOKE ALL ON FUNCTION public.import_legacy_ward(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.import_legacy_ward(uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.assign_ward_unit_facility(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.assign_ward_unit_facility(uuid,uuid) TO authenticated;