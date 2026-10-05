-- Facility administrators may onboard/manage users inside their own facility.
-- System Superuser retains platform-wide membership management.

CREATE OR REPLACE FUNCTION public.platform_set_user_facility_membership(
  _user_id uuid,
  _facility_id uuid,
  _is_active boolean DEFAULT true,
  _access_scope text DEFAULT 'facility'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_actor_facility uuid;
  v_facility public.healthcare_facilities;
  v_membership public.facility_memberships;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT public.has_role(v_actor,'system_superuser'::public.app_role)
     AND NOT public.has_role(v_actor,'admin'::public.app_role)
     AND NOT public.has_role(v_actor,'it_admin'::public.app_role) THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=_user_id) THEN
    RAISE EXCEPTION 'Target user not found';
  END IF;

  IF _access_scope NOT IN ('facility','district','regional','national') THEN
    RAISE EXCEPTION 'Unsupported facility access scope';
  END IF;

  SELECT * INTO v_facility
  FROM public.healthcare_facilities
  WHERE id=_facility_id;

  IF v_facility.id IS NULL THEN
    RAISE EXCEPTION 'Facility not found';
  END IF;

  IF _is_active AND NOT v_facility.is_active THEN
    RAISE EXCEPTION 'Cannot activate membership for an inactive facility';
  END IF;

  IF NOT public.has_role(v_actor,'system_superuser'::public.app_role) THEN
    SELECT uaf.facility_id INTO v_actor_facility
    FROM public.user_active_facilities uaf
    WHERE uaf.user_id=v_actor
    LIMIT 1;

    IF v_actor_facility IS NULL THEN
      RAISE EXCEPTION 'An active facility context is required';
    END IF;

    IF v_actor_facility <> _facility_id THEN
      RAISE EXCEPTION 'Facility membership is outside your active facility';
    END IF;

    -- Facility administrators cannot grant broader geographic scopes.
    IF _access_scope <> 'facility' THEN
      RAISE EXCEPTION 'Facility administrators may only grant facility scope';
    END IF;
  END IF;

  INSERT INTO public.facility_memberships(facility_id,user_id,access_scope,is_active)
  VALUES(_facility_id,_user_id,_access_scope,_is_active)
  ON CONFLICT(facility_id,user_id) DO UPDATE
    SET access_scope=EXCLUDED.access_scope,is_active=EXCLUDED.is_active
  RETURNING * INTO v_membership;

  IF NOT _is_active AND public.has_role(v_actor,'system_superuser'::public.app_role) THEN
    DELETE FROM public.user_active_facilities
    WHERE user_id=_user_id AND facility_id=_facility_id;
  END IF;

  INSERT INTO public.system_audit_log(actor_id,action,module,entity_type,entity_id,severity,metadata)
  VALUES(v_actor,'platform_set_user_facility_membership','administration','facility_membership',v_membership.id,'info',
    pg_catalog.jsonb_build_object(
      'target_user_id',_user_id,'facility_id',_facility_id,
      'is_active',_is_active,'access_scope',_access_scope,'changed_by',v_actor
    ));

  RETURN pg_catalog.jsonb_build_object(
    'ok',true,'membership_id',v_membership.id,'user_id',_user_id,
    'facility_id',_facility_id,'is_active',_is_active,'access_scope',_access_scope
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.platform_set_user_active_facility(
  _user_id uuid,
  _facility_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_actor_facility uuid;
  v_membership public.facility_memberships;
  v_facility public.healthcare_facilities;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  IF NOT public.has_role(v_actor,'system_superuser'::public.app_role) THEN
    RAISE EXCEPTION 'Only a System Superuser can set another user active facility context';
  END IF;

  SELECT * INTO v_membership
  FROM public.facility_memberships
  WHERE user_id=_user_id AND facility_id=_facility_id AND is_active=true;

  IF v_membership.id IS NULL THEN
    RAISE EXCEPTION 'User must have an active membership before selecting active facility context';
  END IF;

  SELECT * INTO v_facility FROM public.healthcare_facilities WHERE id=_facility_id;
  IF v_facility.id IS NULL OR NOT v_facility.is_active THEN
    RAISE EXCEPTION 'Facility is not active';
  END IF;

  IF NOT public.has_role(v_actor,'system_superuser'::public.app_role) THEN
    SELECT uaf.facility_id INTO v_actor_facility
    FROM public.user_active_facilities uaf
    WHERE uaf.user_id=v_actor
    LIMIT 1;

    IF v_actor_facility IS NULL THEN RAISE EXCEPTION 'An active facility context is required'; END IF;
    IF v_actor_facility <> _facility_id THEN
      RAISE EXCEPTION 'Facility context is outside your active facility';
    END IF;
  END IF;

  INSERT INTO public.user_active_facilities(user_id,facility_id,updated_at)
  VALUES(_user_id,_facility_id,pg_catalog.now())
  ON CONFLICT(user_id) DO UPDATE SET facility_id=EXCLUDED.facility_id,updated_at=EXCLUDED.updated_at;

  INSERT INTO public.system_audit_log(actor_id,action,module,entity_type,entity_id,severity,metadata)
  VALUES(v_actor,'platform_set_user_active_facility','administration','user_active_facility',_user_id,'info',
    pg_catalog.jsonb_build_object('target_user_id',_user_id,'facility_id',_facility_id,'changed_by',v_actor));

  RETURN pg_catalog.jsonb_build_object('ok',true,'user_id',_user_id,'facility_id',_facility_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.platform_set_user_facility_membership(uuid,uuid,boolean,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.platform_set_user_active_facility(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.platform_set_user_facility_membership(uuid,uuid,boolean,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.platform_set_user_active_facility(uuid,uuid) TO authenticated;

NOTIFY pgrst,'reload schema';