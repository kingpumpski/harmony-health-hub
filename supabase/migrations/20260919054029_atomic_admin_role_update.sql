-- Make administrator role changes atomic at the database boundary.
CREATE OR REPLACE FUNCTION public.admin_update_user_role(_target_user_id UUID,_next_role public.app_role)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_actor UUID := auth.uid();
BEGIN
 IF v_actor IS NULL OR NOT public.has_role(v_actor,'admin'::public.app_role) THEN RAISE EXCEPTION 'Administrator access required'; END IF;
 IF _target_user_id IS NULL THEN RAISE EXCEPTION 'Target user is required'; END IF;
 IF _target_user_id=v_actor AND _next_role<>'admin'::public.app_role THEN RAISE EXCEPTION 'Administrators cannot remove their own admin role'; END IF;
 IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=_target_user_id) THEN RAISE EXCEPTION 'Target user not found'; END IF;
 DELETE FROM public.user_roles WHERE user_id=_target_user_id;
 INSERT INTO public.user_roles(user_id,role) VALUES(_target_user_id,_next_role);
 PERFORM public.record_system_audit(_action:='admin_update_user_role',_module:='administration',_entity_type:='user',_entity_id:=_target_user_id,_severity:='info',_metadata:=jsonb_build_object('assigned_role',_next_role,'target_user_id',_target_user_id,'actor_user_id',v_actor));
 RETURN jsonb_build_object('ok',true,'user',jsonb_build_object('id',_target_user_id,'role',_next_role));
END; $$;
REVOKE ALL ON FUNCTION public.admin_update_user_role(UUID,public.app_role) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_update_user_role(UUID,public.app_role) TO authenticated;