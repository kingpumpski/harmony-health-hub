-- Replace the legacy broad clinical-role helper in exposed workflow functions.
-- The helper includes accountant, front_desk and canteen, which are not clinical
-- roles for these specific data/workflow boundaries.

CREATE OR REPLACE FUNCTION public.acknowledge_vital_alert(_alert_id UUID)
RETURNS public.vital_alerts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  uid UUID := auth.uid();
  result public.vital_alerts;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN
    RAISE EXCEPTION 'Not authorized to acknowledge vital alerts';
  END IF;

  UPDATE public.vital_alerts
  SET acknowledged_by = uid,
      acknowledged_at = COALESCE(acknowledged_at, pg_catalog.now())
  WHERE id = _alert_id
    AND acknowledged_at IS NULL
  RETURNING * INTO result;

  IF result.id IS NULL THEN
    SELECT * INTO result FROM public.vital_alerts WHERE id = _alert_id FOR UPDATE;
    IF result.id IS NULL THEN RAISE EXCEPTION 'Vital alert not found'; END IF;
  END IF;

  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_meal_plan_workflow(
  _patient_id UUID,
  _plan_type TEXT,
  _restrictions TEXT DEFAULT NULL
)
RETURNS public.meal_plans
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  uid UUID := auth.uid();
  v_plan public.meal_plans;
  v_type TEXT := NULLIF(pg_catalog.btrim(COALESCE(_plan_type, '')), '');
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
    OR public.has_role(uid,'canteen')
  ) THEN
    RAISE EXCEPTION 'Meal plan creation is not permitted';
  END IF;
  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients p WHERE p.id = _patient_id
  ) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;
  IF v_type IS NULL THEN RAISE EXCEPTION 'Meal plan type is required'; END IF;

  INSERT INTO public.meal_plans(
    patient_id, plan_type, restrictions, created_by, active
  ) VALUES (
    _patient_id,
    v_type,
    NULLIF(pg_catalog.btrim(COALESCE(_restrictions, '')), ''),
    uid,
    TRUE
  )
  RETURNING * INTO v_plan;

  PERFORM public.record_system_audit(
    'meal_plan_created',
    'canteen',
    'meal_plan',
    v_plan.id,
    'info',
    pg_catalog.jsonb_build_object(
      'patient_id', _patient_id,
      'plan_type', v_type,
      'actor_user_id', uid
    )
  );

  RETURN v_plan;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_department_queue(
  _department TEXT,
  _limit INTEGER DEFAULT 100
)
RETURNS TABLE(
  id UUID,
  department TEXT,
  status TEXT,
  queued_at TIMESTAMPTZ,
  service_order_id UUID,
  service_name TEXT,
  amount NUMERIC,
  service_order_status TEXT,
  patient_id UUID,
  patient_first_name TEXT,
  patient_last_name TEXT,
  patient_code TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_department TEXT := NULLIF(btrim(_department),'');
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_department IS NULL THEN RETURN; END IF;
  IF _limit IS NULL OR _limit < 1 OR _limit > 500 THEN RAISE EXCEPTION 'Invalid queue limit'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'accountant')
    OR public.has_role(auth.uid(),'practitioner')
    OR public.has_role(auth.uid(),'nurse')
    OR public.has_role(auth.uid(),'midwife')
    OR public.has_role(auth.uid(),'specialist_nurse')
    OR public.has_role(auth.uid(),'lab_technician')
    OR public.has_role(auth.uid(),'radiologist')
    OR public.has_role(auth.uid(),'radiology_technician')
    OR public.has_role(auth.uid(),'pharmacist')
  ) THEN
    RAISE EXCEPTION 'Department queue access denied';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id=auth.uid() AND lower(COALESCE(p.department,''))=lower(v_department)
  ) AND NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Department queue access denied for this department';
  END IF;

  RETURN QUERY
  SELECT q.id,q.department,q.status,q.queued_at,q.service_order_id,
         so.service_name,so.amount,so.status,so.patient_id,
         p.first_name,p.last_name,p.patient_code
  FROM public.department_queues q
  JOIN public.service_orders so ON so.id=q.service_order_id
  JOIN public.patients p ON p.id=so.patient_id
  WHERE lower(q.department)=lower(v_department)
    AND q.status IN ('queued','claimed')
  ORDER BY q.queued_at ASC
  LIMIT _limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_pending_specialist_referrals()
RETURNS TABLE(
  referral_id UUID,
  patient_id UUID,
  patient_name TEXT,
  telephone TEXT,
  specialty TEXT,
  appointment_date TIMESTAMPTZ,
  referred_at TIMESTAMPTZ,
  status TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT (
    public.has_role((SELECT auth.uid()),'admin'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'practitioner'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'nurse'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'midwife'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'specialist_nurse'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Specialist referral access denied';
  END IF;

  RETURN QUERY
  SELECT r.id,r.patient_id,concat(p.first_name,' ',p.last_name),p.phone,
         r.specialty,r.appointment_date,r.created_at,r.status
  FROM public.patient_referrals r
  JOIN public.patients p ON p.id=r.patient_id
  WHERE r.status IN ('requested','accepted','scheduled')
    AND r.specialty IS NOT NULL
  ORDER BY r.appointment_date NULLS LAST,r.created_at ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_meal_order_delivered(_order_id UUID)
RETURNS public.meal_orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  uid UUID := auth.uid();
  v_order public.meal_orders;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
    OR public.has_role(uid,'canteen')
  ) THEN
    RAISE EXCEPTION 'Meal delivery update is not permitted';
  END IF;

  SELECT * INTO v_order
  FROM public.meal_orders
  WHERE id = _order_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Meal order not found'; END IF;
  IF v_order.status = 'delivered' THEN RETURN v_order; END IF;

  UPDATE public.meal_orders
  SET status = 'delivered', delivered_at = COALESCE(delivered_at, pg_catalog.now())
  WHERE id = _order_id
  RETURNING * INTO v_order;

  PERFORM public.record_system_audit(
    'meal_order_delivered',
    'canteen',
    'meal_order',
    v_order.id,
    'info',
    pg_catalog.jsonb_build_object('patient_id', v_order.patient_id, 'actor_user_id', uid)
  );

  RETURN v_order;
END;
$function$;

CREATE OR REPLACE FUNCTION public.patient_coverage_details(_patient_id UUID)
RETURNS TABLE(coverage_type TEXT, payer_name TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT (
    public.has_role((SELECT auth.uid()),'admin'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'accountant'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'front_desk'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'practitioner'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'nurse'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'midwife'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'specialist_nurse'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'lab_technician'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'radiologist'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'radiology_technician'::public.app_role)
    OR public.has_role((SELECT auth.uid()),'pharmacist'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Patient coverage access denied';
  END IF;

  RETURN QUERY
  SELECT
    CASE
      WHEN NULLIF(trim(p.insurance_provider),'') IS NOT NULL THEN 'insurance'
      WHEN NULLIF(trim(p.partner_company),'') IS NOT NULL THEN 'partner_company'
    END,
    COALESCE(
      NULLIF(trim(p.insurance_provider),''),
      NULLIF(trim(p.partner_company),'')
    )
  FROM public.patients p
  WHERE p.id=_patient_id
    AND (
      NULLIF(trim(p.insurance_provider),'') IS NOT NULL
      OR NULLIF(trim(p.partner_company),'') IS NOT NULL
    )
    AND (p.insurance_expiry IS NULL OR p.insurance_expiry>=CURRENT_DATE);
END;
$function$;

REVOKE ALL ON FUNCTION public.acknowledge_vital_alert(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_vital_alert(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.create_meal_plan_workflow(UUID,TEXT,TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_meal_plan_workflow(UUID,TEXT,TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.get_department_queue(TEXT,INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_department_queue(TEXT,INTEGER) TO authenticated;
REVOKE ALL ON FUNCTION public.get_pending_specialist_referrals() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pending_specialist_referrals() TO authenticated;
REVOKE ALL ON FUNCTION public.mark_meal_order_delivered(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_meal_order_delivered(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.patient_coverage_details(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.patient_coverage_details(UUID) TO authenticated;
