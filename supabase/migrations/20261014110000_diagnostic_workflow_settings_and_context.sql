BEGIN;

-- Extend the legacy settings table rather than creating a competing settings source.
-- A missing per-facility row intentionally means ordering is disabled.
ALTER TABLE public.facility_settings
  ADD COLUMN IF NOT EXISTS facility_id uuid REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS allow_radiology_ordering boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS allow_lab_ordering boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS notification_settings jsonb NOT NULL DEFAULT '{}'::jsonb;

DO $block$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.facility_settings'::regclass
      AND conname = 'facility_settings_notification_settings_object_check'
  ) THEN
    ALTER TABLE public.facility_settings
      ADD CONSTRAINT facility_settings_notification_settings_object_check
      CHECK (jsonb_typeof(notification_settings) = 'object');
  END IF;
END;
$block$;

CREATE UNIQUE INDEX IF NOT EXISTS facility_settings_facility_id_uidx
  ON public.facility_settings(facility_id)
  WHERE facility_id IS NOT NULL;

ALTER TABLE public.facility_settings ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.get_facility_workflow_settings()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  facility uuid := public.current_user_facility_id();
  settings_row public.facility_settings%ROWTYPE;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF facility IS NULL THEN
    RETURN pg_catalog.jsonb_build_object(
      'facility_id', NULL,
      'allow_lab_ordering', false,
      'allow_radiology_ordering', false,
      'notification_settings', '{}'::jsonb
    );
  END IF;

  IF NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'it_admin')
    OR public.has_role(uid, 'system_superuser')
    OR public.has_role(uid, 'practitioner')
    OR public.has_role(uid, 'nurse')
    OR public.has_role(uid, 'midwife')
    OR public.has_role(uid, 'specialist_nurse')
    OR public.has_role(uid, 'lab_technician')
    OR public.has_role(uid, 'radiologist')
    OR public.has_role(uid, 'radiology_technician')
  ) THEN
    RAISE EXCEPTION 'Facility workflow settings access is not permitted';
  END IF;

  SELECT fs.* INTO settings_row
  FROM public.facility_settings fs
  WHERE fs.facility_id = facility
  LIMIT 1;

  RETURN pg_catalog.jsonb_build_object(
    'facility_id', facility,
    'allow_lab_ordering', coalesce(settings_row.allow_lab_ordering, false),
    'allow_radiology_ordering', coalesce(settings_row.allow_radiology_ordering, false),
    'notification_settings', coalesce(settings_row.notification_settings, '{}'::jsonb)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_facility_workflow_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_facility_workflow_settings() TO authenticated;

-- Only facility administrators may change ordering switches; defaults remain deny-by-default.
CREATE OR REPLACE FUNCTION public.set_facility_workflow_settings(
  _allow_lab_ordering boolean,
  _allow_radiology_ordering boolean,
  _notification_settings jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  facility uuid := public.current_user_facility_id();
  saved public.facility_settings%ROWTYPE;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT public.has_role(uid, 'admin') THEN
    RAISE EXCEPTION 'Facility administrator role required to change workflow settings';
  END IF;
  IF facility IS NULL THEN RAISE EXCEPTION 'Select an active facility first'; END IF;
  IF _notification_settings IS NULL OR pg_catalog.jsonb_typeof(_notification_settings) <> 'object' THEN
    RAISE EXCEPTION 'Notification settings must be a JSON object';
  END IF;

  INSERT INTO public.facility_settings(
    id, facility_id, allow_lab_ordering, allow_radiology_ordering, notification_settings, updated_at
  ) VALUES (
    'facility:' || facility::text, facility,
    coalesce(_allow_lab_ordering, false), coalesce(_allow_radiology_ordering, false),
    _notification_settings, pg_catalog.now()
  )
  ON CONFLICT (facility_id) WHERE facility_id IS NOT NULL
  DO UPDATE SET
    allow_lab_ordering = EXCLUDED.allow_lab_ordering,
    allow_radiology_ordering = EXCLUDED.allow_radiology_ordering,
    notification_settings = EXCLUDED.notification_settings,
    updated_at = pg_catalog.now()
  RETURNING * INTO saved;

  RETURN pg_catalog.jsonb_build_object(
    'facility_id', saved.facility_id,
    'allow_lab_ordering', saved.allow_lab_ordering,
    'allow_radiology_ordering', saved.allow_radiology_ordering,
    'notification_settings', saved.notification_settings
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.set_facility_workflow_settings(boolean, boolean, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_facility_workflow_settings(boolean, boolean, jsonb) TO authenticated;

-- Notify the ordering clinician when a radiology report becomes complete.
CREATE OR REPLACE FUNCTION public.notify_imaging_result_ready()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.status = 'completed'
     AND OLD.status IS DISTINCT FROM NEW.status
     AND NEW.requested_by IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.notifications n
       WHERE n.recipient_user_id = NEW.requested_by
         AND n.related_entity_id = NEW.id
         AND n.category = 'diagnostic_result'
         AND n.title = 'Radiology result ready'
     ) THEN
    INSERT INTO public.notifications(
      recipient_user_id, title, message, severity, category, link,
      related_patient_id, related_entity_id, metadata
    ) VALUES (
      NEW.requested_by, 'Radiology result ready',
      'The imaging report is complete and ready for clinical review.',
      'info', 'diagnostic_result',
      '/imaging?order=' || NEW.id::text,
      NEW.patient_id, NEW.id,
      pg_catalog.jsonb_build_object('workflow', 'imaging_result_review', 'facility_id', NEW.facility_id)
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_imaging_result_ready ON public.imaging_orders;
CREATE TRIGGER trg_notify_imaging_result_ready
AFTER UPDATE OF status, report, impression ON public.imaging_orders
FOR EACH ROW EXECUTE FUNCTION public.notify_imaging_result_ready();

REVOKE ALL ON FUNCTION public.notify_imaging_result_ready() FROM PUBLIC, anon, authenticated;

-- Critical notifications are broadcast only to active clinical staff with facility
-- membership. Never broadcast patient-identifiable details to unrelated users.
CREATE OR REPLACE FUNCTION public.notify_critical_lab_result()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  is_critical boolean;
  was_critical boolean := false;
  staff record;
BEGIN
  is_critical := coalesce(NEW.is_abnormal, false)
    AND lower(coalesce(NEW.abnormal_flag, '')) IN
      ('critical', 'critical_high', 'critical_low', 'high_critical', 'low_critical');

  IF TG_OP = 'UPDATE' THEN
    was_critical := coalesce(OLD.is_abnormal, false)
      AND lower(coalesce(OLD.abnormal_flag, '')) IN
        ('critical', 'critical_high', 'critical_low', 'high_critical', 'low_critical');
  END IF;

  IF is_critical AND NOT was_critical AND NEW.facility_id IS NOT NULL THEN
    FOR staff IN
      SELECT DISTINCT fm.user_id
      FROM public.facility_memberships fm
      JOIN public.user_roles ur ON ur.user_id = fm.user_id
      WHERE fm.facility_id = NEW.facility_id
        AND fm.is_active = true
        AND ur.role IN (
          'admin'::public.app_role, 'practitioner'::public.app_role,
          'nurse'::public.app_role, 'midwife'::public.app_role,
          'specialist_nurse'::public.app_role, 'lab_technician'::public.app_role,
          'radiologist'::public.app_role, 'radiology_technician'::public.app_role
        )
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.recipient_user_id = staff.user_id
          AND n.related_entity_id = NEW.id
          AND n.category = 'critical_lab_result'
      ) THEN
        INSERT INTO public.notifications(
          recipient_user_id, title, message, severity, category, link,
          related_patient_id, related_entity_id, metadata
        ) VALUES (
          staff.user_id, 'Critical laboratory result',
          'A critical laboratory result requires prompt clinical review.',
          'critical', 'critical_lab_result',
          '/laboratory?order=' || NEW.lab_order_id::text || '&result=' || NEW.id::text,
          NEW.patient_id, NEW.id,
          pg_catalog.jsonb_build_object(
            'workflow', 'critical_lab_result',
            'lab_order_id', NEW.lab_order_id,
            'facility_id', NEW.facility_id,
            'requires_acknowledgement', true
          )
        );
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_critical_lab_result ON public.lab_results;
CREATE TRIGGER trg_notify_critical_lab_result
AFTER INSERT OR UPDATE ON public.lab_results
FOR EACH ROW EXECUTE FUNCTION public.notify_critical_lab_result();

REVOKE ALL ON FUNCTION public.notify_critical_lab_result() FROM PUBLIC, anon, authenticated;

-- When an invoice is paid, notify the relevant diagnostic teams in that facility.
CREATE OR REPLACE FUNCTION public.notify_paid_diagnostic_invoice()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  department_name text;
  staff record;
BEGIN
  IF NEW.status = 'paid' AND OLD.status IS DISTINCT FROM NEW.status AND NEW.facility_id IS NOT NULL THEN
    FOR department_name IN
      SELECT DISTINCT lower(so.department)
      FROM public.service_orders so
      WHERE so.invoice_id = NEW.id
        AND so.facility_id = NEW.facility_id
        AND lower(so.department) IN ('laboratory', 'radiology', 'imaging')
    LOOP
      FOR staff IN
        SELECT DISTINCT fm.user_id
        FROM public.facility_memberships fm
        JOIN public.user_roles ur ON ur.user_id = fm.user_id
        WHERE fm.facility_id = NEW.facility_id
          AND fm.is_active = true
          AND (
            (department_name = 'laboratory' AND ur.role IN ('admin'::public.app_role, 'accountant'::public.app_role, 'lab_technician'::public.app_role))
            OR (department_name IN ('radiology', 'imaging') AND ur.role IN ('admin'::public.app_role, 'accountant'::public.app_role, 'radiologist'::public.app_role, 'radiology_technician'::public.app_role))
          )
      LOOP
        IF NOT EXISTS (
          SELECT 1 FROM public.notifications n
          WHERE n.recipient_user_id = staff.user_id
            AND n.related_entity_id = NEW.id
            AND n.category = 'diagnostic_invoice_paid'
            AND n.metadata ->> 'department' = department_name
        ) THEN
          INSERT INTO public.notifications(
            recipient_user_id, title, message, severity, category, link,
            related_patient_id, related_entity_id, metadata
          ) VALUES (
            staff.user_id, 'Diagnostic invoice paid',
            'A diagnostic invoice has been paid. The related worklist can be refreshed.',
            'info', 'diagnostic_invoice_paid', '/billing',
            NEW.patient_id, NEW.id,
            pg_catalog.jsonb_build_object(
              'workflow', 'diagnostic_invoice_paid',
              'department', department_name,
              'facility_id', NEW.facility_id
            )
          );
        END IF;
      END LOOP;
    END LOOP;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_notify_paid_diagnostic_invoice ON public.invoices;
CREATE TRIGGER trg_notify_paid_diagnostic_invoice
AFTER UPDATE OF status ON public.invoices
FOR EACH ROW EXECUTE FUNCTION public.notify_paid_diagnostic_invoice();

REVOKE ALL ON FUNCTION public.notify_paid_diagnostic_invoice() FROM PUBLIC, anon, authenticated;

-- Give laboratory/radiology staff a governed, read-only view of the encounter
-- that originated an order. Do not expose the encounter table directly.
CREATE OR REPLACE FUNCTION public.get_diagnostic_order_clinical_context(
  _order_id uuid,
  _order_type text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  facility uuid := public.current_user_facility_id();
  order_patient uuid;
  order_encounter uuid;
  order_facility uuid;
  order_notes text;
  v_chief_complaint text;
  v_diagnosis text;
  v_clinical_notes text;
  encounter_row record;
  patient_row record;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF _order_id IS NULL OR _order_type NOT IN ('laboratory', 'imaging') THEN
    RAISE EXCEPTION 'A valid diagnostic order and type are required';
  END IF;
  IF facility IS NULL THEN RAISE EXCEPTION 'Select an active facility first'; END IF;
  IF NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'it_admin')
    OR public.has_role(uid, 'system_superuser')
    OR public.has_role(uid, 'practitioner')
    OR public.has_role(uid, 'nurse')
    OR public.has_role(uid, 'midwife')
    OR public.has_role(uid, 'specialist_nurse')
    OR public.has_role(uid, 'lab_technician')
    OR public.has_role(uid, 'radiologist')
    OR public.has_role(uid, 'radiology_technician')
  ) THEN
    RAISE EXCEPTION 'Diagnostic clinical context access is not permitted';
  END IF;

  IF _order_type = 'laboratory' THEN
    SELECT lo.patient_id, lo.encounter_id, lo.facility_id, lo.clinical_notes
      INTO order_patient, order_encounter, order_facility, order_notes
    FROM public.lab_orders lo
    WHERE lo.id = _order_id;
  ELSE
    SELECT io.patient_id, io.encounter_id, io.facility_id, io.clinical_indication
      INTO order_patient, order_encounter, order_facility, order_notes
    FROM public.imaging_orders io
    WHERE io.id = _order_id;
  END IF;

  IF order_patient IS NULL OR order_facility IS DISTINCT FROM facility THEN
    RAISE EXCEPTION 'Diagnostic order not found in the active facility';
  END IF;

  SELECT p.first_name, p.last_name, p.patient_code, p.facility_id
    INTO patient_row
  FROM public.patients p
  WHERE p.id = order_patient;

  IF NOT FOUND OR patient_row.facility_id IS DISTINCT FROM order_facility THEN
    RAISE EXCEPTION 'Diagnostic order patient facility lineage is unresolved';
  END IF;

  IF order_encounter IS NOT NULL THEN
    SELECT e.id, e.chief_complaint, e.principal_diagnosis, e.clerking_notes,
           e.symptoms, e.facility_id, e.patient_id
      INTO encounter_row
    FROM public.encounters e
    WHERE e.id = order_encounter;

    IF NOT FOUND
       OR encounter_row.patient_id IS DISTINCT FROM order_patient
       OR encounter_row.facility_id IS DISTINCT FROM order_facility THEN
      RAISE EXCEPTION 'Encounter facility or patient lineage is unresolved';
    END IF;
    v_chief_complaint := encounter_row.chief_complaint;
    v_diagnosis := encounter_row.principal_diagnosis;
    v_clinical_notes := coalesce(encounter_row.clerking_notes, encounter_row.symptoms);
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'order_id', _order_id,
    'order_type', _order_type,
    'patient_id', order_patient,
    'patient_name', pg_catalog.concat_ws(' ', patient_row.first_name, patient_row.last_name),
    'patient_code', patient_row.patient_code,
    'encounter_id', order_encounter,
    'chief_complaint', v_chief_complaint,
    'diagnosis', v_diagnosis,
    'clinical_notes', coalesce(v_clinical_notes, order_notes)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_diagnostic_order_clinical_context(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_diagnostic_order_clinical_context(uuid, text) TO authenticated;

-- Existing operational audit triggers and notification queue remain authoritative.
-- Realtime publication is added idempotently; existing row-level policies are preserved.
DO $block$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'notifications'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END;
$block$;

NOTIFY pgrst, 'reload schema';

COMMIT;
