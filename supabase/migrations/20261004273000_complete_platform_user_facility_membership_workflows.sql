BEGIN;

CREATE OR REPLACE FUNCTION public.platform_list_user_facility_memberships(_user_id uuid)
RETURNS TABLE(
  facility_id uuid,
  facility_name text,
  facility_code text,
  facility_is_active boolean,
  membership_is_active boolean,
  access_scope text,
  is_active_context boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(),'system_superuser'::public.app_role) THEN RAISE EXCEPTION 'System Superuser access required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=_user_id) THEN RAISE EXCEPTION 'Target user not found'; END IF;
  RETURN QUERY
  SELECT fm.facility_id,hf.name,hf.facility_code,hf.is_active,fm.is_active,fm.access_scope,
         EXISTS (SELECT 1 FROM public.user_active_facilities uaf WHERE uaf.user_id=_user_id AND uaf.facility_id=fm.facility_id)
  FROM public.facility_memberships fm
  JOIN public.healthcare_facilities hf ON hf.id=fm.facility_id
  WHERE fm.user_id=_user_id
  ORDER BY hf.name,hf.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.platform_set_user_facility_membership(_user_id uuid,_facility_id uuid,_is_active boolean DEFAULT true,_access_scope text DEFAULT 'facility')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_facility public.healthcare_facilities; v_membership public.facility_memberships;
BEGIN
  IF v_actor IS NULL OR NOT public.has_role(v_actor,'system_superuser'::public.app_role) THEN RAISE EXCEPTION 'System Superuser access required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=_user_id) THEN RAISE EXCEPTION 'Target user not found'; END IF;
  IF _access_scope NOT IN ('facility','district','regional','national') THEN RAISE EXCEPTION 'Unsupported facility access scope'; END IF;
  SELECT * INTO v_facility FROM public.healthcare_facilities WHERE id=_facility_id;
  IF v_facility.id IS NULL THEN RAISE EXCEPTION 'Facility not found'; END IF;
  IF _is_active AND NOT v_facility.is_active THEN RAISE EXCEPTION 'Cannot activate membership for an inactive facility'; END IF;
  INSERT INTO public.facility_memberships(facility_id,user_id,access_scope,is_active)
  VALUES(_facility_id,_user_id,_access_scope,_is_active)
  ON CONFLICT(facility_id,user_id) DO UPDATE SET access_scope=EXCLUDED.access_scope,is_active=EXCLUDED.is_active
  RETURNING * INTO v_membership;
  IF NOT _is_active THEN DELETE FROM public.user_active_facilities WHERE user_id=_user_id AND facility_id=_facility_id; END IF;
  INSERT INTO public.system_audit_log(actor_id,action,module,entity_type,entity_id,severity,metadata)
  VALUES(v_actor,'platform_set_user_facility_membership','administration','facility_membership',v_membership.id,'info',
         jsonb_build_object('target_user_id',_user_id,'facility_id',_facility_id,'is_active',_is_active,'access_scope',_access_scope));
  RETURN jsonb_build_object('ok',true,'membership_id',v_membership.id,'user_id',_user_id,'facility_id',_facility_id,'is_active',_is_active,'access_scope',_access_scope);
END;
$function$;

CREATE OR REPLACE FUNCTION public.platform_set_user_active_facility(_user_id uuid,_facility_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_facility public.healthcare_facilities;
BEGIN
  IF v_actor IS NULL OR NOT public.has_role(v_actor,'system_superuser'::public.app_role) THEN RAISE EXCEPTION 'System Superuser access required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=_user_id) THEN RAISE EXCEPTION 'Target user not found'; END IF;
  SELECT hf.* INTO v_facility
  FROM public.healthcare_facilities hf
  JOIN public.facility_memberships fm ON fm.facility_id=hf.id AND fm.user_id=_user_id AND fm.is_active=true
  WHERE hf.id=_facility_id AND hf.is_active=true;
  IF v_facility.id IS NULL THEN RAISE EXCEPTION 'User must have an active membership in an active facility before it can be selected as active context'; END IF;
  INSERT INTO public.user_active_facilities(user_id,facility_id,updated_at) VALUES(_user_id,_facility_id,pg_catalog.now())
  ON CONFLICT(user_id) DO UPDATE SET facility_id=EXCLUDED.facility_id,updated_at=EXCLUDED.updated_at;
  INSERT INTO public.system_audit_log(actor_id,action,module,entity_type,entity_id,severity,metadata)
  VALUES(v_actor,'platform_set_user_active_facility','administration','user_active_facility',_user_id,'info',jsonb_build_object('target_user_id',_user_id,'facility_id',_facility_id));
  RETURN jsonb_build_object('ok',true,'user_id',_user_id,'facility_id',_facility_id,'facility_name',v_facility.name);
END;
$function$;

REVOKE ALL ON FUNCTION public.platform_list_user_facility_memberships(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.platform_set_user_facility_membership(uuid,uuid,boolean,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.platform_set_user_active_facility(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.platform_list_user_facility_memberships(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_set_user_facility_membership(uuid,uuid,boolean,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_set_user_active_facility(uuid,uuid) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;