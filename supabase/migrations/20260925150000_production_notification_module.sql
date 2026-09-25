-- Production Notification Module: event catalog, preferences, templates, scheduling, delivery, audit and feature flags.
ALTER TABLE public.notification_queue
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT,
  ADD COLUMN IF NOT EXISTS tenant_id UUID,
  ADD COLUMN IF NOT EXISTS user_id UUID,
  ADD COLUMN IF NOT EXISTS priority TEXT NOT NULL DEFAULT 'medium',
  ADD COLUMN IF NOT EXISTS event_name TEXT,
  ADD COLUMN IF NOT EXISTS template_key TEXT,
  ADD COLUMN IF NOT EXISTS locale TEXT,
  ADD COLUMN IF NOT EXISTS timezone TEXT,
  ADD COLUMN IF NOT EXISTS scheduled_for TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS fallback_channels JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS last_attempt_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS notification_queue_idempotency_uq ON public.notification_queue(idempotency_key) WHERE idempotency_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.notification_channels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), code TEXT NOT NULL UNIQUE CHECK (code IN ('in_app','email','sms','push','whatsapp','voice')),
  enabled BOOLEAN NOT NULL DEFAULT false, provider TEXT, priority INTEGER NOT NULL DEFAULT 100,
  config JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.notification_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), event_name TEXT NOT NULL UNIQUE, description TEXT NOT NULL, trigger_source TEXT NOT NULL,
  audience JSONB NOT NULL DEFAULT '[]'::jsonb, channel_priority JSONB NOT NULL DEFAULT '["in_app"]'::jsonb,
  priority_level TEXT NOT NULL DEFAULT 'medium' CHECK (priority_level IN ('critical','high','medium','low')),
  quiet_hours_behavior TEXT NOT NULL DEFAULT 'delay' CHECK (quiet_hours_behavior IN ('delay','send','fallback')),
  opt_out_allowed BOOLEAN NOT NULL DEFAULT true, locale_aware BOOLEAN NOT NULL DEFAULT true, template_key TEXT NOT NULL,
  retry_policy JSONB NOT NULL DEFAULT '{"max_attempts":5,"backoff_seconds":[10,30,120,600,3600]}'::jsonb,
  enabled BOOLEAN NOT NULL DEFAULT false, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.notification_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), template_key TEXT NOT NULL, locale TEXT NOT NULL DEFAULT 'en-GH',
  channel TEXT NOT NULL CHECK (channel IN ('in_app','email','sms','push','whatsapp','voice')),
  subject_template TEXT, body_template TEXT NOT NULL, metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  version INTEGER NOT NULL DEFAULT 1, active BOOLEAN NOT NULL DEFAULT true, created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(template_key, locale, channel, version)
);
CREATE INDEX IF NOT EXISTS idx_notification_templates_lookup ON public.notification_templates(template_key, locale, channel, active);

CREATE TABLE IF NOT EXISTS public.user_notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id UUID, user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  locale TEXT NOT NULL DEFAULT 'en-GH', timezone TEXT NOT NULL DEFAULT 'Africa/Accra',
  quiet_hours_start TIME NOT NULL DEFAULT '22:00', quiet_hours_end TIME NOT NULL DEFAULT '07:00',
  pause_non_critical BOOLEAN NOT NULL DEFAULT false,
  channel_preferences JSONB NOT NULL DEFAULT '{"in_app":true,"email":false,"sms":false,"push":false,"whatsapp":false,"voice":false}'::jsonb,
  category_preferences JSONB NOT NULL DEFAULT '{"appointments":true,"medication":true,"clinical":true,"billing":true,"reviews":true,"marketing":false,"greetings":true,"campaigns":false,"wellness":true}'::jsonb,
  consent_version TEXT, consented_at TIMESTAMPTZ, consent_ip INET, updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.notification_consent_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id UUID, user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel TEXT NOT NULL, category TEXT NOT NULL, granted BOOLEAN NOT NULL, consent_version TEXT,
  consented_at TIMESTAMPTZ NOT NULL DEFAULT now(), consent_ip INET, user_agent TEXT
);
CREATE TABLE IF NOT EXISTS public.scheduled_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id UUID, user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  event_name TEXT NOT NULL, template_key TEXT NOT NULL, payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  channels JSONB NOT NULL DEFAULT '["in_app"]'::jsonb, priority TEXT NOT NULL DEFAULT 'medium',
  locale TEXT, timezone TEXT, run_at TIMESTAMPTZ NOT NULL, recurrence TEXT,
  status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','queued','sent','cancelled','failed')),
  idempotency_key TEXT NOT NULL UNIQUE, created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_due ON public.scheduled_notifications(status, run_at);

CREATE TABLE IF NOT EXISTS public.notification_delivery_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id UUID, notification_id UUID REFERENCES public.notifications(id) ON DELETE SET NULL,
  queue_id UUID REFERENCES public.notification_queue(id) ON DELETE SET NULL, user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  channel TEXT NOT NULL, provider TEXT, provider_message_id TEXT,
  status TEXT NOT NULL CHECK (status IN ('queued','sent','delivered','read','clicked','failed','bounced','unsubscribed')),
  attempt INTEGER NOT NULL DEFAULT 1, latency_ms INTEGER, error_code TEXT, error_message TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at TIMESTAMPTZ, read_at TIMESTAMPTZ, clicked_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_notification_delivery_notification ON public.notification_delivery_logs(notification_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notification_delivery_status ON public.notification_delivery_logs(channel, status, created_at DESC);

CREATE TABLE IF NOT EXISTS public.notification_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id UUID, notification_id UUID, queue_id UUID, user_id UUID,
  event_name TEXT, action TEXT NOT NULL, actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, channel TEXT,
  outcome TEXT, reason TEXT, metadata JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.notification_feature_flags (
  key TEXT PRIMARY KEY, enabled BOOLEAN NOT NULL DEFAULT false, rollout_percent INTEGER NOT NULL DEFAULT 0 CHECK (rollout_percent BETWEEN 0 AND 100),
  kill_switch BOOLEAN NOT NULL DEFAULT false, config JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE OR REPLACE FUNCTION public.notification_feature_enabled(_key TEXT, _user_id UUID DEFAULT auth.uid())
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE f public.notification_feature_flags; bucket INTEGER;
BEGIN
  SELECT * INTO f FROM public.notification_feature_flags WHERE key=_key;
  IF NOT FOUND OR NOT f.enabled OR f.kill_switch THEN RETURN FALSE; END IF;
  IF f.rollout_percent >= 100 THEN RETURN TRUE; END IF;
  IF _user_id IS NULL THEN RETURN FALSE; END IF;
  bucket := mod(abs(hashtext(_user_id::text || ':' || _key)),100);
  RETURN bucket < f.rollout_percent;
END; $$;

CREATE OR REPLACE FUNCTION public.ensure_notification_preferences(_user_id UUID)
RETURNS public.user_notification_preferences LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE r public.user_notification_preferences;
BEGIN
  IF auth.uid() IS NULL OR (_user_id <> auth.uid() AND NOT public.has_role(auth.uid(),'admin')) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  INSERT INTO public.user_notification_preferences(user_id) VALUES(_user_id) ON CONFLICT(user_id) DO NOTHING;
  SELECT * INTO r FROM public.user_notification_preferences WHERE user_id=_user_id; RETURN r;
END; $$;

CREATE OR REPLACE FUNCTION public.enqueue_notification_v2(
  _event_name TEXT, _user_id UUID, _payload JSONB, _template_key TEXT,
  _channels JSONB DEFAULT '["in_app"]'::jsonb, _priority TEXT DEFAULT 'medium',
  _scheduled_for TIMESTAMPTZ DEFAULT now(), _idempotency_key TEXT DEFAULT NULL,
  _tenant_id UUID DEFAULT NULL, _locale TEXT DEFAULT NULL, _timezone TEXT DEFAULT NULL, _facility_id UUID DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE qid UUID; idem TEXT := COALESCE(_idempotency_key, _event_name || ':' || _user_id::text || ':' || md5(_payload::text));
BEGIN
  IF auth.uid() IS NULL OR (_user_id <> auth.uid() AND NOT public.has_role(auth.uid(),'admin')) THEN RAISE EXCEPTION 'Forbidden'; END IF;
  IF _facility_id IS NOT NULL AND NOT public.has_facility_access(auth.uid(),_facility_id) THEN RAISE EXCEPTION 'Facility access required'; END IF;
  IF _user_id IS NULL THEN RAISE EXCEPTION 'Notification recipient required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.notification_events WHERE event_name=_event_name AND enabled) THEN RAISE EXCEPTION 'Notification event is disabled or unknown'; END IF;
  INSERT INTO public.notification_queue(channel,payload,status,idempotency_key,tenant_id,user_id,priority,event_name,template_key,locale,timezone,scheduled_for,fallback_channels,next_attempt_at,facility_id)
  VALUES(COALESCE(_channels->>0,'in_app'), _payload, 'pending', idem, _tenant_id, _user_id, _priority, _event_name, _template_key, _locale, _timezone, COALESCE(_scheduled_for,now()), COALESCE(_channels,'["in_app"]'::jsonb), COALESCE(_scheduled_for,now()), _facility_id)
  ON CONFLICT(idempotency_key) DO UPDATE SET updated_at=now() RETURNING id INTO qid;
  IF qid IS NULL THEN SELECT id INTO qid FROM public.notification_queue WHERE idempotency_key=idem; END IF;
  RETURN qid;
END; $$;

REVOKE ALL ON FUNCTION public.notification_feature_enabled(TEXT,UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.notification_feature_enabled(TEXT,UUID) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.ensure_notification_preferences(UUID) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ensure_notification_preferences(UUID) TO authenticated,service_role;

REVOKE ALL ON FUNCTION public.enqueue_notification_v2(TEXT,UUID,JSONB,TEXT,JSONB,TEXT,TIMESTAMPTZ,TEXT,UUID,TEXT,TEXT,UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enqueue_notification_v2(TEXT,UUID,JSONB,TEXT,JSONB,TEXT,TIMESTAMPTZ,TEXT,UUID,TEXT,TEXT,UUID) TO authenticated, service_role;

ALTER TABLE public.notification_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_consent_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scheduled_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_delivery_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_feature_flags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notification preferences own read" ON public.user_notification_preferences FOR SELECT TO authenticated USING(user_id=auth.uid() OR public.has_role(auth.uid(),'admin'));
CREATE POLICY "notification preferences own update" ON public.user_notification_preferences FOR UPDATE TO authenticated USING(user_id=auth.uid() OR public.has_role(auth.uid(),'admin')) WITH CHECK(user_id=auth.uid() OR public.has_role(auth.uid(),'admin'));
CREATE POLICY "notification preferences own insert" ON public.user_notification_preferences FOR INSERT TO authenticated WITH CHECK(user_id=auth.uid() OR public.has_role(auth.uid(),'admin'));
CREATE POLICY "notification consent own read" ON public.notification_consent_audit FOR SELECT TO authenticated USING(user_id=auth.uid() OR public.has_role(auth.uid(),'admin'));
CREATE POLICY "notification templates admin read" ON public.notification_templates FOR SELECT TO authenticated USING(public.has_role(auth.uid(),'admin') OR active=true);
CREATE POLICY "notification events authenticated read" ON public.notification_events FOR SELECT TO authenticated USING(true);
CREATE POLICY "notification channels admin read" ON public.notification_channels FOR SELECT TO authenticated USING(public.has_role(auth.uid(),'admin'));
CREATE POLICY "notification flags admin manage" ON public.notification_feature_flags FOR ALL TO authenticated USING(public.has_role(auth.uid(),'admin')) WITH CHECK(public.has_role(auth.uid(),'admin'));

REVOKE ALL ON public.notification_audit FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.notification_delivery_logs FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.notification_delivery_logs TO authenticated;

CREATE OR REPLACE FUNCTION public.prevent_notification_audit_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Notification audit is immutable'; END; $$;
DROP TRIGGER IF EXISTS notification_audit_immutable ON public.notification_audit;
CREATE TRIGGER notification_audit_immutable BEFORE UPDATE OR DELETE ON public.notification_audit FOR EACH ROW EXECUTE FUNCTION public.prevent_notification_audit_mutation();

INSERT INTO public.notification_channels(code,enabled,provider,priority) VALUES
('in_app',true,'supabase_realtime',10),('email',false,'generic_http',20),('sms',false,'twilio',30),('push',false,'fcm',40),('whatsapp',false,'twilio_whatsapp',50),('voice',false,'twilio_voice',60)
ON CONFLICT(code) DO NOTHING;

INSERT INTO public.notification_feature_flags(key,enabled,rollout_percent) VALUES
('notifications.in_app',true,100),('notifications.email',false,0),('notifications.sms',false,0),('notifications.push',false,0),
('notifications.whatsapp',false,0),('notifications.voice',false,0),('notifications.appointments',false,0),
('notifications.medication',false,0),('notifications.clinical',false,0),('notifications.wellness',false,0),('notifications.marketing',false,0)
ON CONFLICT(key) DO NOTHING;

INSERT INTO public.notification_events(event_name,description,trigger_source,audience,channel_priority,priority_level,quiet_hours_behavior,opt_out_allowed,template_key)
VALUES
('appointment_booked','Appointment created','appointments','["patient","front_desk"]','["in_app","push","sms","email"]','medium','delay',true,'appointment.confirmation'),
('appointment_reminder_24h','Appointment is 24 hours away','scheduler','["patient"]','["push","sms","email","in_app"]','medium','delay',true,'appointment.reminder_24h'),
('appointment_reminder_1h','Appointment is one hour away','scheduler','["patient"]','["push","sms","in_app"]','high','send',true,'appointment.reminder_1h'),
('appointment_rescheduled','Appointment changed','appointments','["patient"]','["in_app","push","sms","email"]','high','send',true,'appointment.rescheduled'),
('appointment_cancelled','Appointment cancelled','appointments','["patient"]','["in_app","push","sms","email"]','high','send',true,'appointment.cancelled'),
('appointment_confirmed','Appointment confirmed','appointments','["patient"]','["in_app","push","email"]','medium','delay',true,'appointment.confirmed'),
('appointment_checked_in','Patient checked in','appointments','["patient","practitioner","front_desk"]','["in_app","push"]','medium','send',false,'appointment.checked_in'),
('consultation_started','Consultation started','encounters','["patient","practitioner"]','["in_app","push"]','medium','send',false,'consultation.started'),
('diagnosis_ready','Diagnosis documented','encounters','["patient","practitioner"]','["in_app","push"]','high','send',false,'diagnosis.ready'),
('treatment_plan_created','Treatment plan created','encounters','["patient"]','["in_app","push","email"]','high','send',false,'treatment.plan_created'),
('lab_test_ordered','Lab test ordered','laboratory','["patient"]','["in_app","push"]','medium','delay',false,'lab.test_ordered'),
('lab_result_ready','Lab result ready','laboratory','["patient","practitioner"]','["in_app","push","email"]','high','send',false,'lab.result_ready'),
('prescription_issued','Prescription issued','pharmacy','["patient"]','["in_app","push"]','high','send',false,'prescription.issued'),
('medication_dose_reminder','Medication dose due','scheduler','["patient","nurse"]','["push","sms","in_app"]','high','send',true,'medication.dose_reminder'),
('medication_missed_dose','Medication dose missed','medication','["patient","nurse"]','["in_app","push","sms"]','high','send',true,'medication.missed_dose'),
('medication_refill_reminder','Medication refill due','scheduler','["patient"]','["push","sms","email","in_app"]','medium','delay',true,'medication.refill'),
('medication_completion','Medication course completed','medication','["patient"]','["in_app","push"]','medium','delay',true,'medication.completion'),
('discharge_summary_ready','Discharge summary ready','inpatient','["patient"]','["in_app","email"]','high','send',false,'discharge.summary_ready'),
('post_discharge_checkin_72h','Post-discharge check-in','scheduler','["patient"]','["push","sms","in_app"]','high','delay',true,'discharge.checkin_72h'),
('followup_appointment_due','Follow-up appointment due','scheduler','["patient"]','["push","sms","email","in_app"]','high','delay',true,'followup.appointment_due'),
('review_request_after_treatment','Review requested','reviews','["patient"]','["push","email","in_app"]','low','delay',true,'review.request'),
('birthday_wish','Birthday greeting','scheduler','["patient"]','["in_app","push","email"]','low','delay',true,'greeting.birthday'),
('seasonal_greeting','Configurable seasonal greeting','campaigns','["patient"]','["in_app","email","push"]','low','delay',true,'greeting.seasonal'),
('annual_checkup_reminder','Annual checkup reminder','scheduler','["patient"]','["push","sms","email","in_app"]','medium','delay',true,'wellness.annual_checkup'),
('welcome_onboarding','Welcome and onboarding','identity','["patient"]','["in_app","email"]','medium','send',false,'account.welcome'),
('profile_incomplete','Profile completion reminder','scheduler','["patient"]','["in_app","email","push"]','low','delay',true,'account.profile_incomplete'),
('password_changed','Password changed','identity','["patient","staff"]','["in_app","email"]','high','send',false,'security.password_changed'),
('security_alert','Security alert','identity','["patient","staff"]','["in_app","email","sms"]','critical','send',false,'security.alert'),
('invoice_ready','Invoice ready','billing','["patient"]','["in_app","email"]','medium','delay',true,'billing.invoice_ready'),
('payment_due','Payment due','billing','["patient"]','["in_app","email","sms"]','medium','delay',true,'billing.payment_due'),
('payment_received','Payment received','billing','["patient"]','["in_app","email"]','medium','delay',false,'billing.payment_received'),
('critical_lab_alert','Critical laboratory result','laboratory','["practitioner","nurse"]','["in_app","push","sms","voice"]','critical','send',false,'critical.lab_alert'),
('abnormal_vitals_alert','Abnormal vital signs','clinical','["practitioner","nurse"]','["in_app","push","sms","voice"]','critical','send',false,'critical.vitals_alert'),
('urgent_care_needed','Urgent care required','clinical','["patient","care_team"]','["in_app","push","sms","voice"]','critical','send',false,'critical.urgent_care'),
('outbreak_alert_in_region','Regional outbreak alert','public_health','["patient"]','["in_app","push","sms"]','high','send',true,'public_health.outbreak'),
('inactive_30d','Patient inactive 30 days','scheduler','["patient"]','["in_app","push","email"]','low','delay',true,'reactivation.inactive_30d'),
('inactive_90d','Patient inactive 90 days','scheduler','["patient"]','["in_app","push","email"]','low','delay',true,'reactivation.inactive_90d')
ON CONFLICT(event_name) DO NOTHING;

INSERT INTO public.notification_templates(template_key,locale,channel,subject_template,body_template)
VALUES
('appointment.confirmation','en-GH','in_app','Appointment confirmed','Your appointment with {{provider_name}} is confirmed for {{appointment_time}}.'),
('appointment.reminder_24h','en-GH','in_app','Appointment reminder','Your appointment is tomorrow at {{appointment_time}}.'),
('appointment.reminder_1h','en-GH','in_app','Appointment reminder','Your appointment starts in about one hour at {{appointment_time}}.'),
('medication.dose_reminder','en-GH','in_app','Medication reminder','It is time for {{medication_name}}. Follow the instructions in your care plan.'),
('lab.result_ready','en-GH','in_app','Lab result ready','A laboratory result is ready for review in your secure health record.'),
('discharge.checkin_72h','en-GH','in_app','How are you doing?','Please complete your post-discharge check-in so your care team can follow up if needed.'),
('review.request','en-GH','in_app','Share your experience','Please share feedback about your recent care.'),
('greeting.birthday','en-GH','in_app','Happy birthday','Wishing you a healthy and happy birthday from the Harmony Health Hub team.'),
('greeting.seasonal','en-GH','in_app','Seasonal greetings','Warm greetings from Harmony Health Hub.'),
('wellness.annual_checkup','en-GH','in_app','Annual check-up reminder','It may be time to schedule your annual health check-up.'),
('critical.lab_alert','en-GH','in_app','Critical clinical alert','A critical result requires prompt clinical attention. Open the clinical workspace for details.')
ON CONFLICT(template_key,locale,channel,version) DO NOTHING;
UPDATE public.notification_events SET enabled=true WHERE event_name IN (
  'appointment_booked','appointment_reminder_24h','appointment_reminder_1h','appointment_rescheduled','appointment_cancelled',
  'appointment_confirmed','appointment_checked_in','consultation_started','diagnosis_ready','treatment_plan_created',
  'lab_test_ordered','lab_result_ready','prescription_issued','medication_dose_reminder','medication_missed_dose',
  'medication_refill_reminder','medication_completion','discharge_summary_ready','post_discharge_checkin_72h',
  'followup_appointment_due','review_request_after_treatment','birthday_wish','seasonal_greeting','annual_checkup_reminder',
  'welcome_onboarding','profile_incomplete','password_changed','security_alert','invoice_ready','payment_due','payment_received',
  'critical_lab_alert','abnormal_vitals_alert','urgent_care_needed','outbreak_alert_in_region','inactive_30d','inactive_90d'
);
