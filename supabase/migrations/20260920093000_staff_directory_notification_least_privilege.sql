-- Least-privilege hardening for staff patient directory and workflow notifications.
-- Forward-only: preserves existing RPC signatures while reducing sensitive exposure
-- and preventing arbitrary notification impersonation.

CREATE OR REPLACE FUNCTION public.search_patient_directory(
  _query text DEFAULT NULL,
  _limit integer DEFAULT 300
)
RETURNS TABLE (
  id uuid,
  patient_code text,
  first_name text,
  last_name text,
  phone text,
  ghana_card_number text,
  status text,
  insurance_provider text,
  insurance_number text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  q text := NULLIF(trim(coalesce(_query, '')), '');
  lim integer := least(greatest(coalesce(_limit, 100), 1), 1000);
  can_sensitive boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    has_role(auth.uid(), 'admin'::app_role)
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
    RAISE EXCEPTION 'Not authorized to access the staff patient directory';
  END IF;

  can_sensitive :=
    has_role(auth.uid(), 'admin'::app_role)
    OR has_role(auth.uid(), 'practitioner'::app_role)
    OR has_role(auth.uid(), 'nurse'::app_role)
    OR has_role(auth.uid(), 'midwife'::app_role)
    OR has_role(auth.uid(), 'specialist_nurse'::app_role)
    OR has_role(auth.uid(), 'accountant'::app_role)
    OR has_role(auth.uid(), 'front_desk'::app_role);

  RETURN QUERY
  SELECT
    p.id,
    p.patient_code,
    p.first_name,
    p.last_name,
    p.phone,
    CASE WHEN can_sensitive THEN p.ghana_card_number ELSE NULL END,
    p.status::text,
    CASE WHEN can_sensitive THEN p.insurance_provider ELSE NULL END,
    CASE WHEN can_sensitive THEN p.insurance_number ELSE NULL END
  FROM public.patients p
  WHERE q IS NULL
     OR p.patient_code ILIKE '%' || q || '%'
     OR p.first_name ILIKE '%' || q || '%'
     OR p.last_name ILIKE '%' || q || '%'
     OR p.phone ILIKE '%' || q || '%'
     OR p.ghana_card_number ILIKE '%' || q || '%'
     OR p.email ILIKE '%' || q || '%'
  ORDER BY p.created_at DESC
  LIMIT lim;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_patient_directory_record(_patient_id uuid)
RETURNS TABLE (
  id uuid,
  patient_code text,
  first_name text,
  last_name text,
  phone text,
  ghana_card_number text,
  status text,
  insurance_provider text,
  insurance_number text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  can_sensitive boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    has_role(auth.uid(), 'admin'::app_role)
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
    RAISE EXCEPTION 'Not authorized to access the staff patient directory';
  END IF;

  can_sensitive :=
    has_role(auth.uid(), 'admin'::app_role)
    OR has_role(auth.uid(), 'practitioner'::app_role)
    OR has_role(auth.uid(), 'nurse'::app_role)
    OR has_role(auth.uid(), 'midwife'::app_role)
    OR has_role(auth.uid(), 'specialist_nurse'::app_role)
    OR has_role(auth.uid(), 'accountant'::app_role)
    OR has_role(auth.uid(), 'front_desk'::app_role);

  RETURN QUERY
  SELECT
    p.id,
    p.patient_code,
    p.first_name,
    p.last_name,
    p.phone,
    CASE WHEN can_sensitive THEN p.ghana_card_number ELSE NULL END,
    p.status::text,
    CASE WHEN can_sensitive THEN p.insurance_provider ELSE NULL END,
    CASE WHEN can_sensitive THEN p.insurance_number ELSE NULL END
  FROM public.patients p
  WHERE p.id = _patient_id;
END;
$$;

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

  IF _recipient_user_id IS NOT NULL AND NOT caller_is_admin AND _recipient_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Non-administrators may only target their own notification inbox';
  END IF;

  IF NULLIF(trim(coalesce(_recipient_role, '')), '') IS NOT NULL THEN
    BEGIN
      requested_role := trim(_recipient_role)::app_role;
    EXCEPTION WHEN invalid_text_representation THEN
      RAISE EXCEPTION 'Unsupported notification recipient role';
    END;

    IF NOT caller_is_admin AND NOT has_role(auth.uid(), requested_role) THEN
      RAISE EXCEPTION 'Caller cannot target the requested recipient role';
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

REVOKE ALL ON FUNCTION public.search_patient_directory(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_patient_directory_record(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_workflow_notification(text, uuid, text, text, text, text, text, uuid, uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_workflow_notifications(integer) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.search_patient_directory(text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_directory_record(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_workflow_notification(text, uuid, text, text, text, text, text, uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_workflow_notifications(integer) TO authenticated;
