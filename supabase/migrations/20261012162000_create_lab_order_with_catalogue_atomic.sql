BEGIN;

-- Preserve the canonical payment-gated order workflow while ensuring that a
-- selected catalogue item is attached in the same transaction. If attachment
-- fails, the lab order and its linked service order roll back together.
CREATE OR REPLACE FUNCTION public.create_lab_order_with_catalogue_atomic(
  _patient_id uuid,
  _test_name text,
  _test_category text,
  _priority text,
  _clinical_notes text,
  _amount numeric,
  _encounter_id uuid,
  _catalogue_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_catalogue public.lab_test_catalogue%ROWTYPE;
  v_response jsonb;
  v_lab_order_id uuid;
  v_facility_id uuid;
  v_rows integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF _catalogue_id IS NOT NULL THEN
    SELECT * INTO v_catalogue
    FROM public.lab_test_catalogue
    WHERE id = _catalogue_id AND active = true
    FOR SHARE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Selected laboratory catalogue item is missing or inactive';
    END IF;
    IF pg_catalog.lower(pg_catalog.btrim(coalesce(_test_name,''))) IS DISTINCT FROM pg_catalog.lower(v_catalogue.test_name) THEN
      RAISE EXCEPTION 'Laboratory test name must match the selected catalogue item';
    END IF;
    IF pg_catalog.lower(pg_catalog.btrim(coalesce(_test_category,''))) IS DISTINCT FROM pg_catalog.lower(coalesce(v_catalogue.category,'')) THEN
      RAISE EXCEPTION 'Laboratory test category must match the selected catalogue item';
    END IF;
  END IF;

  -- The existing RPC remains the single authority for clinical role,
  -- patient/facility, encounter, amount, and payment-gate validation.
  v_response := public.create_lab_order_with_payment_gate(
    _patient_id,
    _test_name,
    _test_category,
    _priority,
    _clinical_notes,
    _amount,
    _encounter_id
  );

  IF _catalogue_id IS NOT NULL THEN
    v_lab_order_id := nullif(v_response->>'lab_order_id', '')::uuid;
    v_facility_id := public.current_user_facility_id();

    IF v_lab_order_id IS NULL THEN
      RAISE EXCEPTION 'Laboratory order creation did not return an order identifier';
    END IF;

    UPDATE public.lab_orders
    SET lab_test_catalogue_id = _catalogue_id,
        updated_at = pg_catalog.now()
    WHERE id = v_lab_order_id
      AND facility_id IS NOT NULL
      AND (
        (public.has_role(v_uid,'admin'::public.app_role) OR public.has_role(v_uid,'it_admin'::public.app_role))
        OR facility_id = v_facility_id
      );

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows <> 1 THEN
      RAISE EXCEPTION 'Could not attach the selected catalogue item within the order facility context';
    END IF;
  END IF;

  RETURN v_response;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_lab_order_with_catalogue_atomic(uuid,text,text,text,text,numeric,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_lab_order_with_catalogue_atomic(uuid,text,text,text,text,numeric,uuid,uuid) TO authenticated;

COMMIT;
