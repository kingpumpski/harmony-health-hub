-- Keep notification mutations server-authoritative and scoped to the recipient.
CREATE OR REPLACE FUNCTION public.can_manage_notification(_notification_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN FALSE;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.notifications n
    LEFT JOIN public.profiles p ON p.id = auth.uid()
    WHERE n.id = _notification_id
      AND (
        n.recipient_user_id = auth.uid()
        OR (
          n.recipient_role IS NOT NULL
          AND p.role IS NOT NULL
          AND p.role::text = n.recipient_role
        )
      )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_notification_read(_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_manage_notification(_notification_id) THEN
    RAISE EXCEPTION 'Notification access denied';
  END IF;

  UPDATE public.notifications
  SET is_read = TRUE
  WHERE id = _notification_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_notifications_read(_notification_ids UUID[])
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  changed_count INTEGER;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  UPDATE public.notifications n
  SET is_read = TRUE
  WHERE n.id = ANY(_notification_ids)
    AND (
      n.recipient_user_id = auth.uid()
      OR EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
          AND n.recipient_role IS NOT NULL
          AND p.role IS NOT NULL
          AND p.role::text = n.recipient_role
      )
    )
    AND n.is_read = FALSE;

  GET DIAGNOSTICS changed_count = ROW_COUNT;
  RETURN changed_count;
END;
$$;

REVOKE ALL ON FUNCTION public.can_manage_notification(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_notification_read(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_notifications_read(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notifications_read(UUID[]) TO authenticated;

-- Notification recipients should not mutate the table directly; creation remains
-- controlled by the existing notification service/RPC paths.
REVOKE UPDATE ON public.notifications FROM authenticated;
