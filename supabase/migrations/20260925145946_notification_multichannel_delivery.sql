-- Production-grade multichannel notification delivery contracts.\n\n-- The queue is an internal outbox. Clients must never enqueue or rewrite delivery state directly.
REVOKE ALL ON TABLE public.notification_queue FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.notification_queue TO service_role;


-- In-app remains the canonical notification record. External channels are queued,
-- retried and audited independently so provider failure never blocks clinical UI.

CREATE TABLE IF NOT EXISTS public.notification_channel_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email_enabled boolean NOT NULL DEFAULT false,
  sms_enabled boolean NOT NULL DEFAULT false,
  push_enabled boolean NOT NULL DEFAULT false,
  whatsapp_enabled boolean NOT NULL DEFAULT false,
  allow_clinical_content boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.notification_channel_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users manage own notification channel preferences" ON public.notification_channel_preferences;
CREATE POLICY "users manage own notification channel preferences"
  ON public.notification_channel_preferences
  FOR ALL TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE INDEX IF NOT EXISTS notification_channel_preferences_email_idx
  ON public.notification_channel_preferences(user_id) WHERE email_enabled;
CREATE INDEX IF NOT EXISTS notification_channel_preferences_sms_idx
  ON public.notification_channel_preferences(user_id) WHERE sms_enabled;
CREATE INDEX IF NOT EXISTS notification_channel_preferences_push_idx
  ON public.notification_channel_preferences(user_id) WHERE push_enabled;
CREATE INDEX IF NOT EXISTS notification_channel_preferences_whatsapp_idx
  ON public.notification_channel_preferences(user_id) WHERE whatsapp_enabled;

CREATE TABLE IF NOT EXISTS public.notification_push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint text NOT NULL,
  subscription jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, endpoint)
);

ALTER TABLE public.notification_push_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users manage own push subscriptions" ON public.notification_push_subscriptions;
CREATE POLICY "users manage own push subscriptions"
  ON public.notification_push_subscriptions
  FOR ALL TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (user_id = auth.uid() OR public.has_role(auth.uid(), 'admin'::public.app_role));

CREATE INDEX IF NOT EXISTS notification_push_subscriptions_user_idx
  ON public.notification_push_subscriptions(user_id);

CREATE TABLE IF NOT EXISTS public.notification_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_id uuid NOT NULL REFERENCES public.notification_queue(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  channel text NOT NULL,
  provider text,
  destination_hash text,
  status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  provider_message_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz,
  UNIQUE (queue_id, user_id, channel)
);

CREATE INDEX IF NOT EXISTS notification_deliveries_status_idx
  ON public.notification_deliveries(status, updated_at DESC);

ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_deliveries FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_notification_deliveries_touch ON public.notification_deliveries;
CREATE TRIGGER trg_notification_deliveries_touch
  BEFORE UPDATE ON public.notification_deliveries
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- External channel fan-out is service-only. Preferences default to off so enabling
-- a provider never silently exposes patient/staff contact data.
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
  -- Internal SECURITY DEFINER helper; it is not executable by client roles.

  SELECT * INTO n FROM public.notifications WHERE id = _notification_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Notification not found';
  END IF;

  FOR target_user IN
    SELECT ur.user_id
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

-- Extend the existing canonical workflow notification creator without changing
-- its public signature. The in-app record remains synchronous; external delivery
-- is asynchronous and never changes the returned notification id.
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

  -- Queue external channels only when the authenticated workflow caller is
  -- allowed to create the canonical notification. The queue worker performs
  -- provider calls outside the request transaction.
  PERFORM public.enqueue_external_notification_channels(new_id);

  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_workflow_notification(text,uuid,text,text,text,text,text,uuid,uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_workflow_notification(text,uuid,text,text,text,text,text,uuid,uuid,jsonb) TO authenticated;
