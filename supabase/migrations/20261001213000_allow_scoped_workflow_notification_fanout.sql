-- Permit only category-scoped workflow broadcasts to operational role inboxes.
-- Appointment creation may be performed by front desk or clinical staff; its
-- notification fan-out must not fail merely because the caller is not each
-- recipient role. Arbitrary user inbox targeting remains admin-only.

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
SET search_path = pg_catalog, public
AS $$
DECLARE
  new_id uuid;
  requested_role app_role;
  normalized_category text := lower(trim(coalesce(_category, 'other')));
  caller_is_admin boolean := has_role(auth.uid(), 'admin'::app_role);
  can_broadcast_category boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    caller_is_admin
    OR has_role(auth.uid(), 'practitioner'::app_role)
    OR has_role(auth.uid(), 'nurse'::app_role)
    OR has_role(auth.uid(), 'midwife'::app_role)
    OR has_role(auth.uid(), 'specialist_nurse'::app_role)
    OR has_role(auth.uid(), 'lab_technician'::app_role)
    OR has_role(auth.uid(), 'radiologist'::app_role)
    OR has_role(auth.uid(), 'pharmacist'::app_role)
    OR has_role(auth.uid(), 'accountant'::app_role)
    OR has_role(auth.uid(), 'front_desk'::app_role)
    OR has_role(auth.uid(), 'canteen'::app_role)
  ) THEN
    RAISE EXCEPTION 'Not authorized to create workflow notifications';
  END IF;

  IF _related_patient_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _related_patient_id) THEN
    RAISE EXCEPTION 'Related patient does not exist';
  END IF;

  -- Only administrators may target another individual user directly.
  IF _recipient_user_id IS NOT NULL AND NOT caller_is_admin AND _recipient_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Non-administrators may only target their own notification inbox';
  END IF;

  IF NULLIF(trim(coalesce(_recipient_role, '')), '') IS NOT NULL THEN
    BEGIN
      requested_role := trim(_recipient_role)::app_role;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'Unsupported notification recipient role';
    END;

    -- Role fan-out is allowed only for known operational category/recipient
    -- pairs, and only when the caller is a role authorized to initiate that
    -- workflow. All other cross-role notifications remain forbidden.
    can_broadcast_category :=
      (normalized_category = 'appointment'
        AND requested_role IN ('practitioner'::app_role, 'nurse'::app_role, 'midwife'::app_role, 'specialist_nurse'::app_role, 'front_desk'::app_role)
        AND (
          has_role(auth.uid(), 'front_desk'::app_role)
          OR has_role(auth.uid(), 'practitioner'::app_role)
          OR has_role(auth.uid(), 'nurse'::app_role)
          OR has_role(auth.uid(), 'midwife'::app_role)
          OR has_role(auth.uid(), 'specialist_nurse'::app_role)
        ))
      OR (normalized_category = 'payment'
        AND requested_role IN ('accountant'::app_role, 'front_desk'::app_role, 'lab_technician'::app_role, 'practitioner'::app_role, 'nurse'::app_role, 'midwife'::app_role, 'specialist_nurse'::app_role, 'radiologist'::app_role, 'radiology_technician'::app_role, 'pharmacist'::app_role)
        AND (
          has_role(auth.uid(), 'practitioner'::app_role)
          OR has_role(auth.uid(), 'nurse'::app_role)
          OR has_role(auth.uid(), 'midwife'::app_role)
          OR has_role(auth.uid(), 'specialist_nurse'::app_role)
          OR has_role(auth.uid(), 'lab_technician'::app_role)
          OR has_role(auth.uid(), 'radiologist'::app_role)
          OR has_role(auth.uid(), 'pharmacist'::app_role)
          OR has_role(auth.uid(), 'accountant'::app_role)
          OR has_role(auth.uid(), 'front_desk'::app_role)
        ))
      OR (normalized_category = 'lab'
        AND requested_role IN ('lab_technician'::app_role, 'practitioner'::app_role, 'nurse'::app_role, 'specialist_nurse'::app_role)
        AND (
          has_role(auth.uid(), 'lab_technician'::app_role)
          OR has_role(auth.uid(), 'practitioner'::app_role)
          OR has_role(auth.uid(), 'nurse'::app_role)
          OR has_role(auth.uid(), 'specialist_nurse'::app_role)
        ))
      OR (normalized_category = 'prescription'
        AND requested_role IN ('pharmacist'::app_role, 'practitioner'::app_role)
        AND (
          has_role(auth.uid(), 'pharmacist'::app_role)
          OR has_role(auth.uid(), 'practitioner'::app_role)
        ))
      OR (normalized_category IN ('triage', 'encounter', 'admission')
        AND requested_role IN ('practitioner'::app_role, 'nurse'::app_role, 'midwife'::app_role, 'specialist_nurse'::app_role)
        AND (
          has_role(auth.uid(), 'practitioner'::app_role)
          OR has_role(auth.uid(), 'nurse'::app_role)
          OR has_role(auth.uid(), 'midwife'::app_role)
          OR has_role(auth.uid(), 'specialist_nurse'::app_role)
        ));

    IF NOT caller_is_admin
       AND NOT has_role(auth.uid(), requested_role)
       AND NOT can_broadcast_category THEN
      RAISE EXCEPTION 'Caller cannot target the requested recipient role for this notification category';
    END IF;
  END IF;

  IF _recipient_user_id IS NULL AND NULLIF(trim(coalesce(_recipient_role, '')), '') IS NULL THEN
    RAISE EXCEPTION 'Notification recipient is required';
  END IF;

  INSERT INTO public.notifications (
    recipient_role, recipient_user_id, title, message, severity, category,
    link, related_patient_id, related_entity_id, metadata
  )
  VALUES (
    NULLIF(_recipient_role, ''), _recipient_user_id, _title, _message,
    COALESCE(NULLIF(_severity, ''), 'info'),
    COALESCE(NULLIF(_category, ''), 'other'),
    _link, _related_patient_id, _related_entity_id, COALESCE(_metadata, '{}'::jsonb)
  )
  RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_workflow_notification(text, uuid, text, text, text, text, text, uuid, uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_workflow_notification(text, uuid, text, text, text, text, text, uuid, uuid, jsonb) TO authenticated;
