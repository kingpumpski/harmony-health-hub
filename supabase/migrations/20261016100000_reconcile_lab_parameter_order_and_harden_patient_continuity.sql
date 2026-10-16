BEGIN;

-- Repair partially provisioned legacy catalogue tables without rewriting data.
ALTER TABLE public.lab_test_parameters
  ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0;

-- Bring already-migrated legacy installations onto the same service-order shape.
-- The matching early migration repair is needed for clean replay; this additive
-- copy ensures existing environments also receive the missing columns.
ALTER TABLE public.facility_settings
  ADD COLUMN IF NOT EXISTS payment_routing_mode TEXT NOT NULL DEFAULT 'streamlined'
    CHECK (payment_routing_mode IN ('pay_before_every_step','streamlined'));

UPDATE public.facility_settings
SET payment_routing_mode = 'pay_before_every_step'
WHERE routing_mode = 'pay_before_each_step'
  AND payment_routing_mode = 'streamlined';

ALTER TABLE public.service_orders
  ADD COLUMN IF NOT EXISTS ordered_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS service_type TEXT NOT NULL DEFAULT 'general',
  ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS fulfillment_status TEXT NOT NULL DEFAULT 'blocked',
  ADD COLUMN IF NOT EXISTS priority TEXT NOT NULL DEFAULT 'routine',
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

UPDATE public.service_orders
SET fulfillment_status = CASE
  WHEN status::text IN ('released','in_progress','completed','cancelled') THEN status::text
  ELSE 'blocked'
END
WHERE fulfillment_status = 'blocked';

-- Reconcile the existing inpatient review table before dependent read/index paths
-- on installations where the table predates the canonical seen_at column.
ALTER TABLE public.inpatient_reviews
  ADD COLUMN IF NOT EXISTS seen_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- This legacy Patient Hub snapshot is SECURITY DEFINER and had its search_path
-- reset to public by a later context-hardening override. Restore safe resolution.
ALTER FUNCTION public.get_patient_hub_snapshot(uuid) SET search_path = '';

-- Patient Hub entrypoint overrides in the earlier context-hardening migration
-- must not reintroduce a public-only search_path for SECURITY DEFINER functions.
ALTER FUNCTION public.create_encounter_workflow(uuid, text, text) SET search_path = '';
ALTER FUNCTION public.record_patient_vitals(uuid, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric) SET search_path = '';
ALTER FUNCTION public.create_patient_lab_order(uuid, text, text) SET search_path = '';
ALTER FUNCTION public.create_patient_document(uuid, text, text, text) SET search_path = '';

-- A ward lifecycle RPC was introduced with a public-only path. Keep pg_catalog
-- first and include auth for auth.uid(); application objects are public-qualified.
ALTER FUNCTION public.complete_ward_bed_cleaning(uuid, text)
  SET search_path = pg_catalog, public, auth;

-- The legacy catalogue attachment RPC was SECURITY DEFINER with a public-only
-- search_path. Include trusted schemas explicitly; all application objects in its
-- body are public-qualified and auth.uid() is resolved through auth.
ALTER FUNCTION public.attach_lab_catalogue_to_order(uuid, uuid)
  SET search_path = pg_catalog, public, auth;

-- The database advisor found this legacy index duplicates the canonical
-- lab_result_id index created by the attachment-column reconciliation migration.
DROP INDEX IF EXISTS public.lab_result_attachments_result_idx;

-- These laboratory read RPCs existed on older deployments with mutable or
-- public-only search paths. Their bodies schema-qualify application objects.
ALTER FUNCTION public.get_laboratory_test_groups(boolean) SET search_path = '';
ALTER FUNCTION public.get_lab_result_attachments(uuid[]) SET search_path = '';
ALTER FUNCTION public.ensure_updated_at() SET search_path = '';

-- Patient-care continuity exposes sensitive clinical domains. Keep trusted
-- schema resolution while retaining its existing role checks and RPC signature.
ALTER FUNCTION public.get_patient_care_continuity(uuid)
  SET search_path = '';

REVOKE ALL ON FUNCTION public.get_patient_care_continuity(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_patient_care_continuity(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
