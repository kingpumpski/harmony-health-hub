-- Keep canteen patient-order reads aligned with the canonical facility lineage.
-- meal_orders, meal_plans, and patients carry facility_id in the canonical schema.
-- Only system_superuser may read across facilities; facility administrators and canteen
-- staff must select an active facility and receive only matching records.

CREATE OR REPLACE FUNCTION public.get_canteen_active_patient_orders()
RETURNS TABLE (
  order_id UUID, patient_id UUID, patient_code TEXT, patient_name TEXT, meal_type TEXT,
  scheduled_for TIMESTAMPTZ, order_status TEXT, plan_type TEXT, dietary_restrictions TEXT,
  underlying_conditions TEXT, current_diagnoses JSONB, meal_notes TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid UUID := auth.uid();
  v_facility UUID;
  v_platform_superuser BOOLEAN;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  v_platform_superuser := public.has_role(uid, 'system_superuser');
  IF NOT (
    v_platform_superuser
    OR public.has_role(uid, 'admin')
    OR public.has_role(uid, 'canteen')
  ) THEN
    RAISE EXCEPTION 'Canteen or administrator role required';
  END IF;

  v_facility := public.current_user_facility_id();
  IF NOT v_platform_superuser AND v_facility IS NULL THEN
    RAISE EXCEPTION 'Select an active facility to access canteen patient orders';
  END IF;

  RETURN QUERY
  SELECT
    mo.id,
    p.id,
    p.patient_code,
    pg_catalog.concat_ws(' ', p.first_name, p.last_name),
    mo.meal_type,
    mo.scheduled_for,
    mo.status,
    mp.plan_type,
    mp.restrictions,
    NULLIF(pg_catalog.btrim(p.chronic_conditions), ''),
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'diagnosis', d.diagnosis,
          'icd_code', d.icd_code,
          'principal', COALESCE(d.is_principal, false),
          'provisional', COALESCE(d.is_provisional, false)
        )
        ORDER BY d.is_principal DESC, d.created_at DESC
      )
      FROM public.diagnoses d
      LEFT JOIN public.encounters e ON e.id = d.encounter_id
      WHERE d.patient_id = p.id
        AND (e.id IS NULL OR e.status NOT IN ('completed', 'cancelled'))
        AND NULLIF(pg_catalog.btrim(d.diagnosis), '') IS NOT NULL
        AND (
          v_platform_superuser
          OR (d.facility_id = v_facility AND e.facility_id = v_facility)
        )
    ), '[]'::jsonb),
    mo.notes
  FROM public.meal_orders mo
  JOIN public.patients p ON p.id = mo.patient_id
  LEFT JOIN public.meal_plans mp
    ON mp.id = mo.meal_plan_id
   AND (
     v_platform_superuser
     OR mp.facility_id = v_facility
   )
   AND mp.patient_id = p.id
  WHERE mo.status <> 'delivered'
    AND mo.scheduled_for >= pg_catalog.now() - INTERVAL '2 hours'
    AND mo.scheduled_for < pg_catalog.now() + INTERVAL '36 hours'
    AND (
      v_platform_superuser
      OR (
        mo.facility_id = v_facility
        AND p.facility_id = v_facility
        AND (mo.meal_plan_id IS NULL OR mp.id IS NOT NULL)
      )
    )
  ORDER BY mo.scheduled_for ASC, p.last_name ASC, p.first_name ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_canteen_active_patient_orders() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_canteen_active_patient_orders() TO authenticated;
NOTIFY pgrst, 'reload schema';
