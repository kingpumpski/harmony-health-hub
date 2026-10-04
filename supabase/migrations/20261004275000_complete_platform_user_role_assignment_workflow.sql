BEGIN;

CREATE OR REPLACE FUNCTION public.platform_set_user_role(_user_id uuid,_role public.app_role)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_facility uuid;
  v_previous public.app_role;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id=v_actor AND role IN ('admin','it_admin','system_superuser')
  ) THEN
    RAISE EXCEPTION 'Administrator access required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=_user_id) THEN RAISE EXCEPTION 'Target user not found'; END IF;
  IF v_actor=_user_id THEN RAISE EXCEPTION 'Administrators cannot change their own role'; END IF;

  SELECT ur.role INTO v_previous
  FROM public.user_roles ur
  WHERE ur.user_id=_user_id
  ORDER BY ur.created_at ASC, ur.role::text ASC
  LIMIT 1;

  IF EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=v_actor AND role='system_superuser') THEN
    NULL;
  ELSE
    IF _role IN ('admin','it_admin','system_superuser') THEN
      RAISE EXCEPTION 'Only a System Superuser can assign platform administrator roles';
    END IF;
    SELECT uaf.facility_id INTO v_facility
    FROM public.user_active_facilities uaf
    JOIN public.healthcare_facilities hf ON hf.id=uaf.facility_id AND hf.is_active=true
    WHERE uaf.user_id=v_actor;
    IF v_facility IS NULL THEN RAISE EXCEPTION 'An active facility context is required before managing facility users'; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.facility_memberships fm
      WHERE fm.user_id=_user_id AND fm.facility_id=v_facility AND fm.is_active=true
    ) THEN
      RAISE EXCEPTION 'Target user is not an active member of your facility';
    END IF;
  END IF;

  DELETE FROM public.user_roles WHERE user_id=_user_id;
  INSERT INTO public.user_roles(user_id,role) VALUES(_user_id,_role);

  INSERT INTO public.system_audit_log(actor_id,action,module,entity_type,entity_id,severity,metadata)
  VALUES(v_actor,'platform_set_user_role','administration','user',_user_id,'info',
    jsonb_build_object('target_user_id',_user_id,'previous_role',v_previous,'role',_role,'facility_id',v_facility));

  RETURN jsonb_build_object('ok',true,'user_id',_user_id,'role',_role,'previous_role',v_previous,'facility_id',v_facility);
END;
$function$;

REVOKE ALL ON FUNCTION public.platform_set_user_role(uuid,public.app_role) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.platform_set_user_role(uuid,public.app_role) TO authenticated;

NOTIFY pgrst,'reload schema';
COMMIT;