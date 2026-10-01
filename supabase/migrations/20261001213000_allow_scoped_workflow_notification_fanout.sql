-- Permit only category-scoped workflow broadcasts to operational role inboxes.
-- Security-definer function uses an empty search_path and fully-qualified objects.
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
SET search_path = ''
AS $$
DECLARE
  new_id uuid;
  requested_role public.app_role;
  normalized_category text := pg_catalog.lower(pg_catalog.trim(pg_catalog.coalesce(_category, 'other')));
  caller_is_admin boolean := public.has_role(auth.uid(), 'admin'::public.app_role);
  can_broadcast_category boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

  IF NOT (
    caller_is_admin
    OR public.has_role(auth.uid(), 'practitioner'::public.app_role)
    OR public.has_role(auth.uid(), 'nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'midwife'::public.app_role)
    OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)
    OR public.has_role(auth.uid(), 'lab_technician'::public.app_role)
    OR public.has_role(auth.uid(), 'radiologist'::public.app_role)
    OR public.has_role(auth.uid(), 'pharmacist'::public.app_role)
    OR public.has_role(auth.uid(), 'accountant'::public.app_role)
    OR public.has_role(auth.uid(), 'front_desk'::public.app_role)
    OR public.has_role(auth.uid(), 'canteen'::public.app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to create workflow notifications'; END IF;

  IF _related_patient_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _related_patient_id) THEN
    RAISE EXCEPTION 'Related patient does not exist';
  END IF;

  IF _recipient_user_id IS NOT NULL AND NOT caller_is_admin AND _recipient_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Non-administrators may only target their own notification inbox';
  END IF;

  IF pg_catalog.nullif(pg_catalog.trim(pg_catalog.coalesce(_recipient_role, '')), '') IS NOT NULL THEN
    BEGIN
      requested_role := pg_catalog.trim(_recipient_role)::public.app_role;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'Unsupported notification recipient role';
    END;

    can_broadcast_category :=
      (normalized_category = 'appointment'
        AND requested_role IN ('practitioner'::public.app_role, 'nurse'::public.app_role, 'midwife'::public.app_role, 'specialist_nurse'::public.app_role, 'front_desk'::public.app_role)
        AND (public.has_role(auth.uid(), 'front_desk'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'midwife'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)))
      OR (normalized_category = 'payment'
        AND requested_role IN ('accountant'::public.app_role, 'front_desk'::public.app_role, 'lab_technician'::public.app_role, 'practitioner'::public.app_role, 'nurse'::public.app_role, 'midwife'::public.app_role, 'specialist_nurse'::public.app_role, 'radiologist'::public.app_role, 'radiology_technician'::public.app_role, 'pharmacist'::public.app_role)
        AND (public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'midwife'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role) OR public.has_role(auth.uid(), 'lab_technician'::public.app_role) OR public.has_role(auth.uid(), 'radiologist'::public.app_role) OR public.has_role(auth.uid(), 'pharmacist'::public.app_role) OR public.has_role(auth.uid(), 'accountant'::public.app_role) OR public.has_role(auth.uid(), 'front_desk'::public.app_role)))
      OR (normalized_category = 'lab'
        AND requested_role IN ('lab_technician'::public.app_role, 'practitioner'::public.app_role, 'nurse'::public.app_role, 'specialist_nurse'::public.app_role)
        AND (public.has_role(auth.uid(), 'lab_technician'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)))
      OR (normalized_category = 'prescription'
        AND requested_role IN ('pharmacist'::public.app_role, 'practitioner'::public.app_role)
        AND (public.has_role(auth.uid(), 'pharmacist'::public.app_role) OR public.has_role(auth.uid(), 'practitioner'::public.app_role)))
      OR (normalized_category IN ('triage', 'encounter', 'admission')
        AND requested_role IN ('practitioner'::public.app_role, 'nurse'::public.app_role, 'midwife'::public.app_role, 'specialist_nurse'::public.app_role)
        AND (public.has_role(auth.uid(), 'practitioner'::public.app_role) OR public.has_role(auth.uid(), 'nurse'::public.app_role) OR public.has_role(auth.uid(), 'midwife'::public.app_role) OR public.has_role(auth.uid(), 'specialist_nurse'::public.app_role)));

    IF NOT caller_is_admin AND NOT public.has_role(auth.uid(), requested_role) AND NOT can_broadcast_category THEN
      RAISE EXCEPTION 'Caller cannot target the requested recipient role for this notification category';
    END IF;
  END IF;

  IF _recipient_user_id IS NULL AND pg_catalog.nullif(pg_catalog.trim(pg_catalog.coalesce(_recipient_role, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Notification recipient is required';
  END IF;

  INSERT INTO public.notifications (
    recipient_role, recipient_user_id, title, message, severity, category,
    link, related_patient_id, related_entity_id, metadata
  )
  VALUES (
    pg_catalog.nullif(_recipient_role, ''), _recipient_user_id, _title, _message,
    pg_catalog.coalesce(pg_catalog.nullif(_severity, ''), 'info'),
    pg_catalog.coalesce(pg_catalog.nullif(_category, ''), 'other'),
    _link, _related_patient_id, _related_entity_id, pg_catalog.coalesce(_metadata, '{}'::jsonb)
  )
  RETURNING id INTO new_id;
  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_workflow_notification(text, uuid, text, text, text, text, text, uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_workflow_notification(text, uuid, text, text, text, text, text, uuid, uuid, jsonb) TO authenticated;
