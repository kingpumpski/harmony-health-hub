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
