-- Next-gen EMPI identity reconciliation.
-- The canonical patient row remains authoritative; source records are retained as
-- merged for traceability. Clinical child rows are re-pointed atomically.

CREATE TABLE IF NOT EXISTS public.patient_identity_merges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_patient_id UUID NOT NULL REFERENCES public.patients(id),
  target_patient_id UUID NOT NULL REFERENCES public.patients(id),
  requested_by UUID NOT NULL REFERENCES auth.users(id),
  approved_by UUID,
  status TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','approved','rejected','completed','failed')),
  reason TEXT NOT NULL,
  affected_tables JSONB NOT NULL DEFAULT '[]'::jsonb,
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  UNIQUE (source_patient_id, target_patient_id, status)
);

CREATE INDEX IF NOT EXISTS idx_patient_identity_merges_source ON public.patient_identity_merges(source_patient_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_patient_identity_merges_target ON public.patient_identity_merges(target_patient_id, requested_at DESC);
ALTER TABLE public.patient_identity_merges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS patient_identity_merges_admin_select ON public.patient_identity_merges;
CREATE POLICY patient_identity_merges_admin_select ON public.patient_identity_merges
  FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS patient_identity_merges_admin_insert ON public.patient_identity_merges;
CREATE POLICY patient_identity_merges_admin_insert ON public.patient_identity_merges
  FOR INSERT TO authenticated WITH CHECK (public.has_role(auth.uid(), 'admin') AND requested_by = auth.uid());

CREATE OR REPLACE FUNCTION public.request_patient_identity_merge(
  _source_patient_id UUID,
  _target_patient_id UUID,
  _reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  merge_id UUID;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'EMPI merge requires administrator authorization';
  END IF;
  IF _source_patient_id IS NULL OR _target_patient_id IS NULL OR _source_patient_id = _target_patient_id THEN
    RAISE EXCEPTION 'Source and target patient records must be distinct';
  END IF;
  IF NULLIF(trim(_reason), '') IS NULL THEN
    RAISE EXCEPTION 'A merge reason is required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _source_patient_id) THEN
    RAISE EXCEPTION 'Source patient does not exist';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _target_patient_id) THEN
    RAISE EXCEPTION 'Target patient does not exist';
  END IF;
  IF EXISTS (SELECT 1 FROM public.patients WHERE id = _source_patient_id AND status = 'merged') THEN
    RAISE EXCEPTION 'Source patient has already been merged';
  END IF;
  IF EXISTS (SELECT 1 FROM public.patients WHERE id = _target_patient_id AND status = 'merged') THEN
    RAISE EXCEPTION 'Target patient cannot be a merged source record';
  END IF;

  INSERT INTO public.patient_identity_merges(source_patient_id,target_patient_id,requested_by,reason)
  VALUES (_source_patient_id,_target_patient_id,auth.uid(),trim(_reason))
  RETURNING id INTO merge_id;
  RETURN merge_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_patient_identity_merge(_merge_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  merge_row public.patient_identity_merges%ROWTYPE;
  table_name TEXT;
  affected JSONB := '[]'::jsonb;
  row_count BIGINT;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'EMPI merge approval requires administrator authorization';
  END IF;

  SELECT * INTO merge_row FROM public.patient_identity_merges WHERE id = _merge_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EMPI merge request not found'; END IF;
  IF merge_row.status <> 'requested' THEN RAISE EXCEPTION 'EMPI merge request is not pending'; END IF;
  IF merge_row.requested_by = auth.uid() THEN
    RAISE EXCEPTION 'A merge requester cannot approve the same merge request';
  END IF;

  PERFORM 1 FROM public.patients WHERE id = merge_row.source_patient_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Source patient record disappeared during merge validation'; END IF;
  PERFORM 1 FROM public.patients WHERE id = merge_row.target_patient_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Target patient record disappeared during merge validation'; END IF;

  -- Re-point only canonical foreign keys that explicitly reference patients(id).
  -- The merge is one transaction: any FK/unique/security failure rolls back all changes.
  FOR table_name IN
    SELECT DISTINCT c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_constraint fk ON fk.conrelid = c.oid
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(fk.conkey)
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND fk.contype = 'f'
      AND fk.confrelid = 'public.patients'::regclass
      AND a.attname = 'patient_id'
      AND c.relname NOT IN ('patients','patient_identity_merges')
  LOOP
    EXECUTE format('UPDATE public.%I SET patient_id = $1 WHERE patient_id = $2', table_name)
      USING merge_row.target_patient_id, merge_row.source_patient_id;
    GET DIAGNOSTICS row_count = ROW_COUNT;
    IF row_count > 0 THEN
      affected := affected || jsonb_build_array(jsonb_build_object('table', table_name, 'rows', row_count));
    END IF;
  END LOOP;

  UPDATE public.patients
  SET status = 'merged', updated_at = now()
  WHERE id = merge_row.source_patient_id;

  UPDATE public.patient_identity_merges
  SET status = 'completed', approved_by = auth.uid(), approved_at = now(), completed_at = now(), affected_tables = affected
  WHERE id = _merge_id;

  RETURN jsonb_build_object('merge_id', _merge_id, 'status', 'completed', 'source_patient_id', merge_row.source_patient_id, 'target_patient_id', merge_row.target_patient_id, 'affected_tables', affected);
END;
$$;

REVOKE ALL ON FUNCTION public.request_patient_identity_merge(UUID,UUID,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.approve_patient_identity_merge(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_patient_identity_merge(UUID,UUID,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_patient_identity_merge(UUID) TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.patient_identity_merges FROM authenticated;
GRANT SELECT ON public.patient_identity_merges TO authenticated;
