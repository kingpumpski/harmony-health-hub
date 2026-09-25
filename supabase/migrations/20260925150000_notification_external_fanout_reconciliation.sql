-- Reconcile notification external fan-out so every direct notification insert can
-- participate in configured external delivery without duplicating legacy queue delivery.

CREATE OR REPLACE FUNCTION public.enqueue_external_notification_channels(
  _notification_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n public.notifications%ROWTYPE;
  target_user uuid;
  queued integer := 0;
BEGIN
  SELECT * INTO n FROM public.notifications WHERE id = _notification_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Notification not found';
  END IF;

  FOR target_user IN
    SELECT DISTINCT ur.user_id
    FROM public.user_roles ur
    WHERE (n.recipient_user_id IS NOT NULL AND ur.user_id = n.recipient_user_id)
       OR (n.recipient_user_id IS NULL AND ur.role = n.recipient_role)
  LOOP
    IF EXISTS (SELECT 1 FROM public.notification_channel_preferences p WHERE p.user_id = target_user AND p.email_enabled) THEN
      INSERT INTO public.notification_queue(channel, payload)
      VALUES ('email', jsonb_build_object('notification_id', n.id, 'recipient_user_id', target_user))
      ON CONFLICT DO NOTHING;
      queued := queued + 1;
    END IF;
    IF EXISTS (SELECT 1 FROM public.notification_channel_preferences p WHERE p.user_id = target_user AND p.sms_enabled) THEN
      INSERT INTO public.notification_queue(channel, payload)
      VALUES ('sms', jsonb_build_object('notification_id', n.id, 'recipient_user_id', target_user))
      ON CONFLICT DO NOTHING;
      queued := queued + 1;
    END IF;
    IF EXISTS (SELECT 1 FROM public.notification_channel_preferences p WHERE p.user_id = target_user AND p.whatsapp_enabled) THEN
      INSERT INTO public.notification_queue(channel, payload)
      VALUES ('whatsapp', jsonb_build_object('notification_id', n.id, 'recipient_user_id', target_user))
      ON CONFLICT DO NOTHING;
      queued := queued + 1;
    END IF;
    IF EXISTS (SELECT 1 FROM public.notification_channel_preferences p WHERE p.user_id = target_user AND p.push_enabled)
       AND EXISTS (SELECT 1 FROM public.notification_push_subscriptions s WHERE s.user_id = target_user) THEN
      INSERT INTO public.notification_queue(channel, payload)
      VALUES ('push', jsonb_build_object('notification_id', n.id, 'recipient_user_id', target_user))
      ON CONFLICT DO NOTHING;
      queued := queued + 1;
    END IF;
  END LOOP;

  RETURN queued;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_external_notification_channels(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_external_notification_channels(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.fanout_notification_after_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.source_queue_id IS NULL THEN
    PERFORM public.enqueue_external_notification_channels(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.fanout_notification_after_insert() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notifications_external_fanout ON public.notifications;
CREATE TRIGGER trg_notifications_external_fanout
AFTER INSERT ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION public.fanout_notification_after_insert();

-- The trigger is now the canonical external fan-out boundary.
CREATE OR REPLACE FUNCTION public.create_workflow_notification(
  _recipient_role text DEFAULT NULL,
  _recipient_user_id uuid DEFAULT NULL,
  _title text DEFAULT '',
  _message text DEFAULT '',
  _severity text DEFAULT 'info',
  _category text DEFAULT 'other',
  _link text DEFAULT NULL,
  _related_patient_id uuid DEFAULT NULL,
  _related_entity_id uuid DEFAULT NULL,
  _metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_id uuid;
  requested_role app_role;
  caller_is_admin boolean := has_role(auth.uid(), 'admin'::app_role);
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    caller_is_admin OR has_role(auth.uid(),'practitioner'::app_role) OR has_role(auth.uid(),'nurse'::app_role)
    OR has_role(auth.uid(),'midwife'::app_role) OR has_role(auth.uid(),'specialist_nurse'::app_role)
    OR has_role(auth.uid(),'lab_technician'::app_role) OR has_role(auth.uid(),'radiologist'::app_role)
    OR has_role(auth.uid(),'pharmacist'::app_role) OR has_role(auth.uid(),'accountant'::app_role)
    OR has_role(auth.uid(),'front_desk'::app_role) OR has_role(auth.uid(),'canteen'::app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to create workflow notifications'; END IF;

  IF _related_patient_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM patients WHERE id = _related_patient_id) THEN
    RAISE EXCEPTION 'Related patient does not exist';
  END IF;
  IF _recipient_user_id IS NOT NULL AND NOT caller_is_admin AND _recipient_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Non-administrators may only target their own notification inbox';
  END IF;
  IF NULLIF(trim(coalesce(_recipient_role,'')),'') IS NOT NULL THEN
    BEGIN requested_role := trim(_recipient_role)::app_role;
    EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'Unsupported notification recipient role'; END;
    IF NOT caller_is_admin AND NOT has_role(auth.uid(), requested_role) THEN
      RAISE EXCEPTION 'Caller cannot target the requested recipient role';
    END IF;
  END IF;
  IF _recipient_user_id IS NULL AND NULLIF(trim(coalesce(_recipient_role,'')),'') IS NULL THEN
    RAISE EXCEPTION 'Notification recipient is required';
  END IF;

  INSERT INTO notifications(recipient_role,recipient_user_id,title,message,severity,category,link,related_patient_id,related_entity_id,metadata)
  VALUES(NULLIF(_recipient_role,''),_recipient_user_id,_title,_message,COALESCE(NULLIF(_severity,''),'info'),
    COALESCE(NULLIF(_category,''),'other'),_link,_related_patient_id,_related_entity_id,COALESCE(_metadata,'{}'::jsonb))
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_workflow_notification(text,uuid,text,text,text,text,text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_workflow_notification(text,uuid,text,text,text,text,text,uuid,uuid,jsonb) TO authenticated;
