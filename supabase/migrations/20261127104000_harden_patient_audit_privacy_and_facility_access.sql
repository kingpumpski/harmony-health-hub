-- Minimize patient audit payloads and bind audit reads to the active facility.
-- Existing historical snapshots are retained; only future trigger writes are minimized.

BEGIN;

REVOKE ALL PRIVILEGES ON TABLE public.patient_audit, public.patient_audit_log
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.patient_audit_log TO authenticated;

-- Preserve the deletion audit event instead of blocking patient deletion.
ALTER TABLE public.patient_audit ALTER COLUMN patient_id DROP NOT NULL;
ALTER TABLE public.patient_audit DROP CONSTRAINT IF EXISTS patient_audit_patient_id_fkey;
ALTER TABLE public.patient_audit
  ADD CONSTRAINT patient_audit_patient_id_fkey
  FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE SET NULL;

DO $$
DECLARE
  policy_row record;
BEGIN
  FOR policy_row IN
    SELECT pol.polname, pol.polrelid::regclass AS relation_name
    FROM pg_policy pol
    WHERE pol.polrelid IN (
      'public.patient_audit'::regclass,
      'public.patient_audit_log'::regclass
    )
  LOOP
    EXECUTE format('DROP POLICY %I ON %s', policy_row.polname, policy_row.relation_name);
  END LOOP;
END;
$$;

ALTER TABLE public.patient_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.patient_audit_log ENABLE ROW LEVEL SECURITY;

-- The legacy snapshot table has no direct client read surface. Its trigger owner
-- remains able to append audit events through SECURITY DEFINER execution.
-- patient_audit_log is the Patient Hub read surface and must follow patient facility.
CREATE POLICY patient_audit_log_active_facility_read
ON public.patient_audit_log
FOR SELECT TO authenticated
USING (
  patient_id IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM public.patients p
    WHERE p.id = patient_audit_log.patient_id
      AND p.facility_id = (SELECT public.current_user_facility_id())
  )
  AND (
    (SELECT public.current_user_is_clinical_staff())
    OR (SELECT public.current_user_has_role('admin'::public.app_role))
  )
);

-- Keep the audit event, actor and changed-field names, but stop copying full
-- patient row values into old_record/new_record on future changes.
CREATE OR REPLACE FUNCTION public.audit_patient_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  changed text[] := ARRAY[]::text[];
BEGIN
  IF TG_OP = 'UPDATE' THEN
    SELECT COALESCE(pg_catalog.array_agg(diff.key ORDER BY diff.key), ARRAY[]::text[])
    INTO changed
    FROM (
      SELECT COALESCE(o.key, n.key) AS key
      FROM pg_catalog.jsonb_each(pg_catalog.to_jsonb(OLD)) o
      FULL JOIN pg_catalog.jsonb_each(pg_catalog.to_jsonb(NEW)) n ON n.key = o.key
      WHERE o.value IS DISTINCT FROM n.value
    ) diff;
  ELSIF TG_OP = 'INSERT' THEN
    changed := ARRAY['record_created'];
  ELSE
    changed := ARRAY['record_deleted'];
  END IF;

  INSERT INTO public.patient_audit_log(
    patient_id, changed_by, action, old_record, new_record, changed_fields
  )
  VALUES (
    CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END,
    auth.uid(),
    TG_OP,
    NULL,
    NULL,
    changed
  );

  RETURN COALESCE(NEW, OLD);
END;
$function$;

CREATE OR REPLACE FUNCTION public.audit_patient_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  changed text[] := ARRAY[]::text[];
BEGIN
  IF TG_OP = 'UPDATE' THEN
    SELECT COALESCE(pg_catalog.array_agg(diff.key ORDER BY diff.key), ARRAY[]::text[])
    INTO changed
    FROM (
      SELECT COALESCE(o.key, n.key) AS key
      FROM pg_catalog.jsonb_each(pg_catalog.to_jsonb(OLD)) o
      FULL JOIN pg_catalog.jsonb_each(pg_catalog.to_jsonb(NEW)) n ON n.key = o.key
      WHERE o.value IS DISTINCT FROM n.value
    ) diff;
  ELSIF TG_OP = 'INSERT' THEN
    changed := ARRAY['record_created'];
  ELSE
    changed := ARRAY['record_deleted'];
  END IF;

  INSERT INTO public.patient_audit(
    patient_id, actor_user_id, operation, changed_fields, old_record, new_record
  )
  VALUES (
    CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END,
    auth.uid(),
    TG_OP,
    pg_catalog.to_jsonb(changed),
    NULL,
    NULL
  );

  RETURN COALESCE(NEW, OLD);
END;
$function$;

REVOKE ALL ON FUNCTION public.audit_patient_changes() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.audit_patient_change() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
