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

-- Patient-care continuity exposes sensitive clinical domains. Keep trusted
-- schema resolution while retaining its existing role checks and RPC signature.
ALTER FUNCTION public.get_patient_care_continuity(uuid)
  SET search_path = '';

REVOKE ALL ON FUNCTION public.get_patient_care_continuity(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_patient_care_continuity(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
