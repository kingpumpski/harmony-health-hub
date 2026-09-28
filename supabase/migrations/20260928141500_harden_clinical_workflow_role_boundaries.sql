-- Tighten client-facing SECURITY DEFINER workflow RPCs that used the
-- broad is_clinical_staff helper. That helper intentionally serves several
-- legacy/RLS compatibility surfaces; these mutations require care roles only.

CREATE OR REPLACE FUNCTION public.complete_service_order(_service_order_id uuid)
RETURNS public.service_orders
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE v_order public.service_orders;
BEGIN
  IF NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'practitioner')
    OR public.has_role(auth.uid(),'nurse')
    OR public.has_role(auth.uid(),'midwife')
    OR public.has_role(auth.uid(),'specialist_nurse')
    OR public.has_role(auth.uid(),'lab_technician')
    OR public.has_role(auth.uid(),'radiologist')
    OR public.has_role(auth.uid(),'radiology_technician')
    OR public.has_role(auth.uid(),'pharmacist')
  ) THEN
    RAISE EXCEPTION 'Clinical staff required';
  END IF;

  UPDATE public.service_orders so
  SET status='completed', completed_at=now(), updated_at=now()
  WHERE so.id=_service_order_id
    AND so.status='in_progress'
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id=auth.uid()
        AND lower(COALESCE(p.department,''))=lower(so.department)
    )
  RETURNING * INTO v_order;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order must be in progress and assigned to your department';
  END IF;

  UPDATE public.department_queues
  SET status='completed', completed_at=now(), updated_at=now()
  WHERE service_order_id=_service_order_id;

  RETURN v_order;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mark_service_order_in_progress(_service_order_id uuid)
RETURNS public.service_orders
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE v_order public.service_orders;
BEGIN
  IF NOT (
    public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'practitioner')
    OR public.has_role(auth.uid(),'nurse')
    OR public.has_role(auth.uid(),'midwife')
    OR public.has_role(auth.uid(),'specialist_nurse')
    OR public.has_role(auth.uid(),'lab_technician')
    OR public.has_role(auth.uid(),'radiologist')
    OR public.has_role(auth.uid(),'radiology_technician')
    OR public.has_role(auth.uid(),'pharmacist')
  ) THEN
    RAISE EXCEPTION 'Clinical staff required';
  END IF;

  UPDATE public.service_orders so
  SET status='in_progress', started_at=COALESCE(started_at,now()), updated_at=now()
  WHERE so.id=_service_order_id
    AND so.status='released'
    AND EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id=auth.uid()
        AND lower(COALESCE(p.department,''))=lower(so.department)
    )
  RETURNING * INTO v_order;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order must be released and assigned to your department';
  END IF;

  UPDATE public.department_queues
  SET status='claimed', claimed_by=auth.uid(), assigned_to=auth.uid(),
      claimed_at=COALESCE(claimed_at,now()), updated_at=now()
  WHERE service_order_id=_service_order_id;

  RETURN v_order;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_treatment_template_workflow(
  _name text,
  _diagnosis text DEFAULT NULL,
  _description text DEFAULT NULL,
  _prescriptions jsonb DEFAULT '[]'::jsonb
)
RETURNS public.treatment_templates
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_template public.treatment_templates;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
    OR public.has_role(uid,'pharmacist')
  ) THEN
    RAISE EXCEPTION 'Clinical role required to create treatment templates';
  END IF;

  IF NULLIF(pg_catalog.btrim(_name), '') IS NULL THEN
    RAISE EXCEPTION 'Template name is required';
  END IF;

  IF _prescriptions IS NULL OR jsonb_typeof(_prescriptions) <> 'array' THEN
    RAISE EXCEPTION 'Prescriptions must be a JSON array';
  END IF;

  INSERT INTO public.treatment_templates
    (name, diagnosis, description, prescriptions, created_by)
  VALUES
    (pg_catalog.btrim(_name),
     NULLIF(pg_catalog.btrim(_diagnosis), ''),
     NULLIF(pg_catalog.btrim(_description), ''),
     _prescriptions, uid)
  RETURNING * INTO v_template;

  PERFORM public.record_system_audit(
    'treatment_template_created',
    'clinical',
    'treatment_template',
    v_template.id,
    'info',
    pg_catalog.jsonb_build_object(
      'created_by', uid,
      'diagnosis', v_template.diagnosis
    )
  );

  RETURN v_template;
END;
$function$;

REVOKE ALL ON FUNCTION public.complete_service_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_service_order(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.mark_service_order_in_progress(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_service_order_in_progress(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.create_treatment_template_workflow(text,text,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_treatment_template_workflow(text,text,text,jsonb) TO authenticated;
