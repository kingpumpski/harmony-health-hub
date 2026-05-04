
-- Notification delivery queue (retries + backoff)
CREATE TABLE IF NOT EXISTS public.notification_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  channel text NOT NULL DEFAULT 'in_app', -- in_app | email | sms
  payload jsonb NOT NULL,                  -- {recipient_role, recipient_user_id, title, message, severity, category, link, related_patient_id, related_entity_id}
  status text NOT NULL DEFAULT 'pending',  -- pending | processing | delivered | failed
  attempts integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 5,
  last_error text,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz
);

CREATE INDEX IF NOT EXISTS notification_queue_due_idx
  ON public.notification_queue(status, next_attempt_at)
  WHERE status IN ('pending','processing');

ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "nq_staff_read" ON public.notification_queue
  FOR SELECT TO authenticated
  USING (is_clinical_staff(auth.uid()) OR has_role(auth.uid(),'admin'));

CREATE POLICY "nq_staff_write" ON public.notification_queue
  FOR ALL TO authenticated
  USING (is_clinical_staff(auth.uid()) OR has_role(auth.uid(),'admin'))
  WITH CHECK (is_clinical_staff(auth.uid()) OR has_role(auth.uid(),'admin'));

CREATE TRIGGER trg_nq_touch
  BEFORE UPDATE ON public.notification_queue
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Helper to enqueue a notification
CREATE OR REPLACE FUNCTION public.enqueue_notification(_payload jsonb, _channel text DEFAULT 'in_app')
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE new_id uuid;
BEGIN
  INSERT INTO public.notification_queue(channel, payload)
  VALUES (_channel, _payload)
  RETURNING id INTO new_id;
  RETURN new_id;
END;
$$;

-- Bulk import jobs
CREATE TABLE IF NOT EXISTS public.bulk_import_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity text NOT NULL, -- patients | pharmacy_inventory | icd_codes | staff
  filename text,
  total_rows integer NOT NULL DEFAULT 0,
  inserted_rows integer NOT NULL DEFAULT 0,
  failed_rows integer NOT NULL DEFAULT 0,
  errors jsonb NOT NULL DEFAULT '[]'::jsonb,
  status text NOT NULL DEFAULT 'completed', -- running | completed | failed
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.bulk_import_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bij_admin_all" ON public.bulk_import_jobs
  FOR ALL TO authenticated
  USING (has_role(auth.uid(),'admin'))
  WITH CHECK (has_role(auth.uid(),'admin'));

-- Update vital-alert trigger to also enqueue for resilient delivery
CREATE OR REPLACE FUNCTION public.check_critical_vitals()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  alert_msgs TEXT[] := ARRAY[]::TEXT[];
  alert_severity TEXT := 'warning';
  r app_role;
BEGIN
  IF NEW.systolic IS NOT NULL AND (NEW.systolic >= 180 OR NEW.systolic <= 90) THEN
    alert_msgs := array_append(alert_msgs, 'BP systolic ' || NEW.systolic);
    alert_severity := 'critical';
  END IF;
  IF NEW.diastolic IS NOT NULL AND (NEW.diastolic >= 120 OR NEW.diastolic <= 60) THEN
    alert_msgs := array_append(alert_msgs, 'BP diastolic ' || NEW.diastolic);
    alert_severity := 'critical';
  END IF;
  IF NEW.temperature IS NOT NULL AND (NEW.temperature >= 39 OR NEW.temperature <= 35) THEN
    alert_msgs := array_append(alert_msgs, 'Temp ' || NEW.temperature || '°C');
    alert_severity := 'critical';
  END IF;
  IF NEW.oxygen_saturation IS NOT NULL AND NEW.oxygen_saturation <= 92 THEN
    alert_msgs := array_append(alert_msgs, 'SpO2 ' || NEW.oxygen_saturation || '%');
    alert_severity := 'critical';
  END IF;
  IF NEW.pulse_rate IS NOT NULL AND (NEW.pulse_rate >= 130 OR NEW.pulse_rate <= 40) THEN
    alert_msgs := array_append(alert_msgs, 'HR ' || NEW.pulse_rate);
    alert_severity := 'critical';
  END IF;

  IF array_length(alert_msgs,1) IS NOT NULL THEN
    INSERT INTO public.vital_alerts(patient_id, vital_signs_id, alert_type, severity, details)
    VALUES (NEW.patient_id, NEW.id, 'abnormal_vitals', alert_severity, array_to_string(alert_msgs, ' · '));

    -- Direct notifications
    INSERT INTO public.notifications(recipient_role, title, message, severity, category, related_patient_id, related_entity_id)
    SELECT r2, '🚨 Critical vitals',
           'Patient requires immediate attention: ' || array_to_string(alert_msgs, ' · '),
           'critical', 'triage', NEW.patient_id, NEW.id
    FROM unnest(ARRAY['practitioner','nurse','admin']::app_role[]) AS r2;

    -- Enqueue for resilient redelivery (in case clients are offline)
    FOREACH r IN ARRAY ARRAY['practitioner','nurse','admin']::app_role[] LOOP
      INSERT INTO public.notification_queue(channel, payload) VALUES (
        'in_app',
        jsonb_build_object(
          'recipient_role', r,
          'title', '🚨 Critical vitals',
          'message', 'Patient requires immediate attention: ' || array_to_string(alert_msgs, ' · '),
          'severity', 'critical',
          'category', 'triage',
          'related_patient_id', NEW.patient_id,
          'related_entity_id', NEW.id
        )
      );
    END LOOP;
  END IF;

  RETURN NEW;
END; $function$;
