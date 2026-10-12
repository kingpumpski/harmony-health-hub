BEGIN;

CREATE TABLE IF NOT EXISTS public.lab_specimens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_order_id uuid NOT NULL REFERENCES public.lab_orders(id) ON DELETE RESTRICT,
  accession_number text NOT NULL UNIQUE,
  barcode_value text NOT NULL UNIQUE,
  specimen_type text,
  status text NOT NULL DEFAULT 'collected'
    CHECK (status IN ('collected','received','processing','rejected')),
  collected_by uuid NOT NULL REFERENCES auth.users(id),
  collected_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  rejected_by uuid REFERENCES auth.users(id),
  rejected_at timestamptz,
  rejection_reason text,
  recollection_of_id uuid REFERENCES public.lab_specimens(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT lab_specimens_rejection_consistency CHECK (
    (status = 'rejected' AND rejected_by IS NOT NULL AND rejected_at IS NOT NULL
      AND nullif(pg_catalog.btrim(rejection_reason), '') IS NOT NULL)
    OR
    (status <> 'rejected' AND rejected_by IS NULL AND rejected_at IS NULL AND rejection_reason IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_lab_specimens_order_collected
  ON public.lab_specimens(lab_order_id, collected_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_lab_specimens_one_active_per_order
  ON public.lab_specimens(lab_order_id)
  WHERE status IN ('collected','received','processing');

ALTER TABLE public.lab_specimens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lab_specimens FROM PUBLIC, anon, authenticated;

-- Collection and accessioning happen in one transaction. The canonical payment,
-- role, encounter, and facility checks remain in this workflow.
CREATE OR REPLACE FUNCTION public.collect_lab_sample(_lab_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_patient_facility uuid;
  o public.lab_orders%ROWTYPE;
  g public.service_orders%ROWTYPE;
  v_specimen_id uuid;
  v_previous_specimen_id uuid;
  v_accession text;
  v_specimen_type text;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'lab_technician') OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse') OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Laboratory clinical role required'; END IF;

  SELECT * INTO o FROM public.lab_orders WHERE id=_lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p WHERE p.id=o.patient_id FOR SHARE;
  IF NOT FOUND OR v_patient_facility IS NULL THEN
    RAISE EXCEPTION 'Laboratory patient facility attribution is unresolved';
  END IF;
  IF o.facility_id IS NULL THEN RAISE EXCEPTION 'Laboratory order facility attribution is unresolved'; END IF;
  IF v_patient_facility IS DISTINCT FROM o.facility_id THEN
    RAISE EXCEPTION 'Laboratory order and patient facility lineage do not match';
  END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin'))
     AND (v_facility IS NULL OR o.facility_id IS DISTINCT FROM v_facility) THEN
    RAISE EXCEPTION 'Laboratory order belongs to a different facility context';
  END IF;
  IF o.status<>'ordered' THEN RAISE EXCEPTION 'Only ordered laboratory requests can have samples collected'; END IF;

  SELECT * INTO g FROM public.service_orders
  WHERE related_entity_id=o.id AND department='laboratory' AND patient_id=o.patient_id
  ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  IF g.id IS NOT NULL AND (g.facility_id IS NULL OR g.facility_id IS DISTINCT FROM o.facility_id) THEN
    RAISE EXCEPTION 'Laboratory payment record facility lineage is unresolved or mismatched';
  END IF;
  IF g.id IS NOT NULL AND g.status NOT IN ('released','in_progress','completed') THEN
    RAISE EXCEPTION 'Payment approval required before sample collection';
  END IF;

  IF o.lab_test_catalogue_id IS NOT NULL THEN
    SELECT c.specimen_type INTO v_specimen_type
    FROM public.lab_test_catalogue c
    WHERE c.id=o.lab_test_catalogue_id AND c.active=true;
  END IF;

  SELECT id INTO v_previous_specimen_id
  FROM public.lab_specimens
  WHERE lab_order_id=o.id AND status='rejected'
  ORDER BY rejected_at DESC
  LIMIT 1;

  v_accession := 'LAB-' || pg_catalog.to_char(pg_catalog.now() AT TIME ZONE 'UTC','YYYYMMDD')
    || '-' || pg_catalog.upper(pg_catalog.left(o.id::text,8))
    || '-' || pg_catalog.upper(pg_catalog.left(gen_random_uuid()::text,8));

  INSERT INTO public.lab_specimens(
    lab_order_id, accession_number, barcode_value, specimen_type, status, collected_by, recollection_of_id
  ) VALUES (
    o.id, v_accession, v_accession, v_specimen_type, 'collected', uid, v_previous_specimen_id
  ) RETURNING id INTO v_specimen_id;

  UPDATE public.lab_orders
  SET status='sample_collected', collected_by=uid,
      sample_collected_at=pg_catalog.now(), updated_at=pg_catalog.now()
  WHERE id=o.id;

  RETURN jsonb_build_object(
    'lab_order_id',o.id,'specimen_id',v_specimen_id,
    'accession_number',v_accession,'barcode_value',v_accession,
    'status','sample_collected'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.reject_lab_specimen(_specimen_id uuid, _reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_patient_facility uuid;
  s public.lab_specimens%ROWTYPE;
  o public.lab_orders%ROWTYPE;
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR public.has_role(uid,'lab_technician')
  ) THEN RAISE EXCEPTION 'Laboratory technician role required'; END IF;
  IF pg_catalog.length(pg_catalog.btrim(coalesce(_reason,''))) < 3
     OR pg_catalog.length(pg_catalog.btrim(coalesce(_reason,''))) > 1000 THEN
    RAISE EXCEPTION 'Provide a specimen rejection reason between 3 and 1000 characters';
  END IF;

  SELECT * INTO s FROM public.lab_specimens WHERE id=_specimen_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory specimen not found'; END IF;
  SELECT * INTO o FROM public.lab_orders WHERE id=s.lab_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Laboratory order not found'; END IF;
  SELECT p.facility_id INTO v_patient_facility
  FROM public.patients p WHERE p.id=o.patient_id FOR SHARE;
  IF NOT FOUND OR v_patient_facility IS NULL THEN
    RAISE EXCEPTION 'Laboratory patient facility attribution is unresolved';
  END IF;
  IF o.facility_id IS NULL THEN RAISE EXCEPTION 'Laboratory order facility attribution is unresolved'; END IF;
  IF v_patient_facility IS DISTINCT FROM o.facility_id THEN
    RAISE EXCEPTION 'Laboratory order and patient facility lineage do not match';
  END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin'))
     AND (v_facility IS NULL OR o.facility_id IS DISTINCT FROM v_facility) THEN
    RAISE EXCEPTION 'Laboratory specimen belongs to a different facility context';
  END IF;
  IF s.status NOT IN ('collected','received') THEN
    RAISE EXCEPTION 'Only collected or received specimens may be rejected';
  END IF;
  IF o.status <> 'sample_collected' THEN
    RAISE EXCEPTION 'Specimen rejection is only allowed before result entry';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lab_results r WHERE r.lab_order_id=o.id
  ) THEN
    RAISE EXCEPTION 'A laboratory result already exists; specimen rejection is no longer permitted';
  END IF;

  UPDATE public.lab_specimens
  SET status='rejected', rejected_by=uid, rejected_at=pg_catalog.now(),
      rejection_reason=pg_catalog.btrim(_reason), updated_at=pg_catalog.now()
  WHERE id=s.id;
  UPDATE public.lab_orders
  SET status='ordered', collected_by=NULL, sample_collected_at=NULL, updated_at=pg_catalog.now()
  WHERE id=o.id AND status='sample_collected';

  PERFORM public.record_system_audit(
    'lab_specimen_rejected','laboratory','lab_specimens',s.id,'warning',
    jsonb_build_object('lab_order_id',o.id,'accession_number',s.accession_number,'reason',pg_catalog.btrim(_reason))
  );

  RETURN jsonb_build_object('specimen_id',s.id,'lab_order_id',o.id,'status','rejected');
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_laboratory_specimens(_limit integer DEFAULT 300)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_department text;
  result jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility to access laboratory specimens'; END IF;
  SELECT NULLIF(pg_catalog.lower(pg_catalog.btrim(p.department)), '') INTO v_department
  FROM public.profiles p WHERE p.id=uid;
  IF NOT (
    public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')
    OR (public.has_role(uid,'lab_technician') AND (v_department IS NULL OR v_department='laboratory'))
  ) THEN RAISE EXCEPTION 'Laboratory specimen access is not permitted'; END IF;
  _limit := LEAST(GREATEST(coalesce(_limit,300),1),500);
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.collected_at DESC),'[]'::jsonb)
  INTO result
  FROM (
    SELECT s.id,s.lab_order_id,s.accession_number,s.barcode_value,s.specimen_type,s.status,
      s.collected_by,s.collected_at,s.rejected_by,s.rejected_at,s.rejection_reason,s.recollection_of_id
    FROM public.lab_specimens s
    JOIN public.lab_orders o ON o.id=s.lab_order_id
    JOIN public.patients p ON p.id=o.patient_id AND p.facility_id=v_facility
    WHERE o.facility_id=v_facility
    ORDER BY s.collected_at DESC LIMIT _limit
  ) x;
  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.collect_lab_sample(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.collect_lab_sample(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.reject_lab_specimen(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_lab_specimen(uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_laboratory_specimens(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_specimens(integer) TO authenticated;

COMMIT;
