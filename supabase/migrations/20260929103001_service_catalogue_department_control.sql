BEGIN;
CREATE OR REPLACE FUNCTION public.update_service_catalogue_item(
  _id uuid,
  _service_code text,
  _service_name text,
  _department text,
  _unit text,
  _amount numeric,
  _currency text DEFAULT 'GHS',
  _active boolean DEFAULT true
)
RETURNS public.service_tariffs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  r public.service_tariffs;
  uid uuid := auth.uid();
  actor_department text;
  target_department text := lower(pg_catalog.btrim(coalesce(_department,'')));
  existing_department text;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _id IS NULL THEN RAISE EXCEPTION 'Service is required'; END IF;
  IF length(pg_catalog.btrim(coalesce(_service_code,''))) < 2 THEN RAISE EXCEPTION 'Service code is required'; END IF;
  IF length(pg_catalog.btrim(coalesce(_service_name,''))) < 2 THEN RAISE EXCEPTION 'Service name is required'; END IF;
  IF target_department = '' THEN RAISE EXCEPTION 'Department is required'; END IF;
  IF coalesce(_amount,0) < 0 THEN RAISE EXCEPTION 'Service amount cannot be negative'; END IF;

  SELECT lower(pg_catalog.btrim(coalesce(p.department,''))) INTO actor_department
  FROM public.profiles p WHERE p.id = uid;

  SELECT lower(pg_catalog.btrim(coalesce(st.department,''))) INTO existing_department
  FROM public.service_tariffs st WHERE st.id = _id FOR UPDATE;

  IF existing_department IS NULL THEN RAISE EXCEPTION 'Service not found'; END IF;

  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    IF NOT public.current_user_has_catalogue_create_permission('create_services') THEN
      RAISE EXCEPTION 'Service configuration privilege required';
    END IF;
    IF actor_department = '' OR existing_department <> actor_department OR target_department <> actor_department THEN
      RAISE EXCEPTION 'You may modify services only for your department';
    END IF;
  END IF;

  UPDATE public.service_tariffs
  SET service_code=upper(pg_catalog.btrim(_service_code)),
      service_name=pg_catalog.btrim(_service_name),
      department=target_department,
      unit=coalesce(nullif(pg_catalog.btrim(_unit),''),'unit'),
      amount=coalesce(_amount,0),
      currency=upper(coalesce(nullif(pg_catalog.btrim(_currency),''),'GHS')),
      active=coalesce(_active,true),
      updated_at=now()
  WHERE id=_id
  RETURNING * INTO r;

  PERFORM public.record_system_audit(
    'service_catalogue_updated','billing','service_tariffs',r.id,'info',
    jsonb_build_object('service_code',r.service_code,'service_name',r.service_name,
      'department',r.department,'active',r.active,'actor_id',uid)
  );
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public.update_service_catalogue_item(uuid,text,text,text,text,numeric,text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_service_catalogue_item(uuid,text,text,text,text,numeric,text,boolean) TO authenticated;
COMMIT;