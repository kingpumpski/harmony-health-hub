BEGIN;

DROP FUNCTION IF EXISTS public.get_canteen_active_patient_orders();

CREATE FUNCTION public.get_canteen_active_patient_orders()
RETURNS TABLE (
  order_id UUID,
  patient_id UUID,
  patient_code TEXT,
  patient_name TEXT,
  meal_type TEXT,
  scheduled_for TIMESTAMPTZ,
  order_status TEXT,
  plan_type TEXT,
  dietary_restrictions TEXT,
  underlying_conditions TEXT,
  current_diagnoses JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE uid UUID := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'canteen')) THEN RAISE EXCEPTION 'Canteen or administrator role required'; END IF;
  RETURN QUERY
  SELECT mo.id,p.id,p.patient_code,pg_catalog.concat_ws(' ',p.first_name,p.last_name),mo.meal_type,mo.scheduled_for,mo.status,
    mp.plan_type,mp.restrictions,NULLIF(pg_catalog.btrim(p.chronic_conditions),''),
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object('diagnosis',d.diagnosis,'icd_code',d.icd_code,'principal',COALESCE(d.is_principal,false),'provisional',COALESCE(d.is_provisional,false)) ORDER BY d.is_principal DESC,d.created_at DESC)
      FROM public.diagnoses d LEFT JOIN public.encounters e ON e.id=d.encounter_id
      WHERE d.patient_id=p.id AND (e.id IS NULL OR e.status NOT IN ('completed','cancelled'))
        AND NULLIF(pg_catalog.btrim(d.diagnosis),'') IS NOT NULL
    ),'[]'::jsonb)
  FROM public.meal_orders mo
  JOIN public.patients p ON p.id=mo.patient_id
  LEFT JOIN public.meal_plans mp ON mp.id=mo.meal_plan_id
  WHERE mo.status <> 'delivered'
    AND mo.scheduled_for >= pg_catalog.now() - INTERVAL '2 hours'
    AND mo.scheduled_for < pg_catalog.now() + INTERVAL '36 hours'
  ORDER BY mo.scheduled_for ASC,p.last_name ASC,p.first_name ASC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_canteen_active_patient_orders() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_canteen_active_patient_orders() TO authenticated;

COMMIT;
