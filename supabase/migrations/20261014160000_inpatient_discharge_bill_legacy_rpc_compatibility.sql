BEGIN;

-- Compatibility overload for browser bundles that still call the historical
-- two-argument signature. The canonical three-argument function remains the
-- source of truth for authorization, facility lineage, and billing projection.
CREATE OR REPLACE FUNCTION public.get_inpatient_discharge_bill(
  _patient_id uuid,
  _to timestamptz DEFAULT now()
)
RETURNS TABLE(
  admission_id uuid,
  patient_id uuid,
  invoice_id uuid,
  invoice_item_id uuid,
  source_type text,
  source_id uuid,
  description text,
  category text,
  department text,
  quantity integer,
  unit_price numeric,
  amount numeric,
  paid_amount numeric,
  outstanding_amount numeric,
  service_order_id uuid,
  service_order_status text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_admission_id uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT a.id
    INTO v_admission_id
  FROM public.admissions a
  WHERE a.patient_id = _patient_id
    AND a.admitted_at <= coalesce(_to, pg_catalog.now())
    AND (a.discharged_at IS NULL OR a.discharged_at >= a.admitted_at)
    AND (
      public.has_role(uid, 'system_superuser'::public.app_role)
      OR public.has_role(uid, 'admin'::public.app_role)
      OR public.has_role(uid, 'it_admin'::public.app_role)
      OR (v_facility IS NOT NULL AND a.facility_id = v_facility)
    )
  ORDER BY
    CASE WHEN a.discharged_at IS NULL THEN 0 ELSE 1 END,
    a.admitted_at DESC
  LIMIT 1;

  IF v_admission_id IS NULL THEN
    RAISE EXCEPTION 'No accessible inpatient admission was found for this patient';
  END IF;

  RETURN QUERY
  SELECT b.*
  FROM public.get_inpatient_discharge_bill(_patient_id, v_admission_id, _to) AS b;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_inpatient_discharge_bill(uuid,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_inpatient_discharge_bill(uuid,timestamptz) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
