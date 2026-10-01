-- Fix notification inserts after the recipient role has been validated.
-- notifications.recipient_role is app_role, while the RPC argument is text.
CREATE OR REPLACE FUNCTION public.create_workflow_notification(
  _recipient_role text DEFAULT NULL::text,
  _recipient_user_id uuid DEFAULT NULL::uuid,
  _title text DEFAULT ''::text,
  _message text DEFAULT ''::text,
  _severity text DEFAULT 'info'::text,
  _category text DEFAULT 'other'::text,
  _link text DEFAULT NULL::text,
  _related_patient_id uuid DEFAULT NULL::uuid,
  _related_entity_id uuid DEFAULT NULL::uuid,
  _metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  new_id uuid;
  requested_role app_role;
  caller_is_admin boolean := public.has_role(auth.uid(), 'admin'::public.app_role);
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    caller_is_admin OR public.has_role(auth.uid(),'practitioner'::public.app_role) OR public.has_role(auth.uid(),'nurse'::public.app_role)
    OR public.has_role(auth.uid(),'midwife'::public.app_role) OR public.has_role(auth.uid(),'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(),'lab_technician'::public.app_role) OR public.has_role(auth.uid(),'radiologist'::public.app_role)
    OR public.has_role(auth.uid(),'pharmacist'::public.app_role) OR public.has_role(auth.uid(),'accountant'::public.app_role)
    OR public.has_role(auth.uid(),'front_desk'::public.app_role) OR public.has_role(auth.uid(),'canteen'::public.app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to create workflow notifications'; END IF;

  IF _related_patient_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _related_patient_id) THEN
    RAISE EXCEPTION 'Related patient does not exist';
  END IF;
  IF _recipient_user_id IS NOT NULL AND NOT caller_is_admin AND _recipient_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Non-administrators may only target their own notification inbox';
  END IF;
  IF NULLIF(trim(coalesce(_recipient_role,'')),'') IS NOT NULL THEN
    BEGIN requested_role := trim(_recipient_role)::public.app_role;
    EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'Unsupported notification recipient role'; END;
    IF NOT caller_is_admin AND NOT public.has_role(auth.uid(), requested_role) THEN
      RAISE EXCEPTION 'Caller cannot target the requested recipient role';
    END IF;
  END IF;
  IF _recipient_user_id IS NULL AND NULLIF(trim(coalesce(_recipient_role,'')),'') IS NULL THEN
    RAISE EXCEPTION 'Notification recipient is required';
  END IF;

  INSERT INTO public.notifications(recipient_role,recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata)
  VALUES(NULLIF(_recipient_role,'')::public.app_role,_recipient_user_id,_title,_message,COALESCE(NULLIF(_severity,''),'info'),
    COALESCE(NULLIF(_category,''),'other'),_link,_related_patient_id,_related_entity_id,COALESCE(_metadata,'{}'::jsonb))
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_workflow_notification(text, uuid, text, text, text, text, text, uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_workflow_notification(text, uuid, text, text, text, text, text, uuid, uuid, jsonb) TO authenticated;
NOTIFY pgrst, 'reload schema';
