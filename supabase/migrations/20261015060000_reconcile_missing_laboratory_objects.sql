BEGIN;

CREATE TABLE IF NOT EXISTS public.lab_test_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id uuid NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  group_name text NOT NULL CHECK (length(btrim(group_name)) BETWEEN 2 AND 120),
  group_code text NOT NULL CHECK (length(btrim(group_code)) BETWEEN 2 AND 40),
  description text,
  default_charge numeric NOT NULL DEFAULT 0 CHECK (default_charge >= 0),
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS lab_test_groups_facility_code_uidx
  ON public.lab_test_groups(facility_id, lower(group_code));

CREATE TABLE IF NOT EXISTS public.lab_test_group_items (
  group_id uuid NOT NULL REFERENCES public.lab_test_groups(id) ON DELETE CASCADE,
  test_id uuid NOT NULL REFERENCES public.lab_test_catalogue(id) ON DELETE RESTRICT,
  display_order integer NOT NULL CHECK (display_order >= 0),
  PRIMARY KEY (group_id, test_id),
  UNIQUE (group_id, display_order)
);

CREATE INDEX IF NOT EXISTS lab_test_group_items_test_id_idx
  ON public.lab_test_group_items(test_id);

ALTER TABLE public.lab_orders
  ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES public.lab_test_groups(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS parent_order_id uuid REFERENCES public.lab_orders(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX IF NOT EXISTS lab_orders_panel_child_test_uidx
  ON public.lab_orders(parent_order_id, lab_test_catalogue_id)
  WHERE parent_order_id IS NOT NULL;

ALTER TABLE public.lab_test_catalogue
  ADD COLUMN IF NOT EXISTS sample_quantity text;

ALTER TABLE public.lab_test_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lab_test_group_items ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lab_test_groups, public.lab_test_group_items
  FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.lab_result_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_order_id uuid NOT NULL REFERENCES public.lab_orders(id) ON DELETE CASCADE,
  lab_result_id uuid REFERENCES public.lab_results(id) ON DELETE SET NULL,
  facility_id uuid NOT NULL,
  storage_path text NOT NULL UNIQUE,
  file_name text NOT NULL,
  mime_type text NOT NULL CHECK (mime_type IN ('application/pdf','image/jpeg','image/png')),
  file_size_bytes bigint NOT NULL CHECK (file_size_bytes BETWEEN 1 AND 15728640),
  uploaded_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Reconcile partially provisioned attachment tables before policies and RPCs
-- reference the canonical columns. Do not invent a storage path or patient/order
-- relationship for legacy rows that cannot be linked safely.
ALTER TABLE public.lab_result_attachments
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS lab_order_id uuid,
  ADD COLUMN IF NOT EXISTS lab_result_id uuid,
  ADD COLUMN IF NOT EXISTS facility_id uuid,
  ADD COLUMN IF NOT EXISTS storage_path text,
  ADD COLUMN IF NOT EXISTS file_name text,
  ADD COLUMN IF NOT EXISTS mime_type text,
  ADD COLUMN IF NOT EXISTS file_size_bytes bigint,
  ADD COLUMN IF NOT EXISTS uploaded_by uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- Backfill only technical metadata that can be generated without inventing a
-- clinical relationship. Legacy attachments without an order or storage path
-- remain preserved but cannot be returned by the guarded read RPC.
UPDATE public.lab_result_attachments
SET id = gen_random_uuid()
WHERE id IS NULL;

UPDATE public.lab_result_attachments
SET created_at = now()
WHERE created_at IS NULL;

ALTER TABLE public.lab_result_attachments
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN id SET NOT NULL,
  ALTER COLUMN created_at SET DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS lab_result_attachments_id_legacy_uidx
  ON public.lab_result_attachments(id);

-- Recover facility scope only where the order linkage is unambiguous. Existing
-- non-null facility IDs are deliberately not overwritten if they disagree.
UPDATE public.lab_result_attachments AS attachment
SET facility_id = lo.facility_id
FROM public.lab_orders AS lo
WHERE attachment.facility_id IS NULL
  AND attachment.lab_order_id = lo.id;

-- Existing installations may contain incomplete or duplicated storage metadata.
-- Preserve those rows for explicit review, but never make ambiguous paths readable.
CREATE INDEX IF NOT EXISTS lab_result_attachments_order_facility_idx
  ON public.lab_result_attachments(lab_order_id, facility_id);

-- Enforce unique paths where legacy data permits it. Existing duplicates are
-- retained for review and excluded from reads rather than guessed or rewritten.
DO $attachment_path_uniqueness$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.lab_result_attachments
    WHERE storage_path IS NOT NULL
    GROUP BY storage_path
    HAVING count(*) > 1
  ) THEN
    EXECUTE 'CREATE UNIQUE INDEX IF NOT EXISTS lab_result_attachments_storage_path_legacy_uidx
      ON public.lab_result_attachments(storage_path)
      WHERE storage_path IS NOT NULL';
  ELSE
    RAISE NOTICE 'Duplicate legacy attachment storage paths detected; ambiguous paths will remain unreadable until reviewed.';
  END IF;
END;
$attachment_path_uniqueness$;

ALTER TABLE public.lab_result_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lab_result_attachments FROM PUBLIC, anon;
GRANT SELECT, INSERT ON TABLE public.lab_result_attachments TO authenticated;

DROP POLICY IF EXISTS lab_result_attachments_facility_read ON public.lab_result_attachments;
CREATE POLICY lab_result_attachments_facility_read
  ON public.lab_result_attachments FOR SELECT TO authenticated
  USING (
    facility_id = (SELECT public.current_user_facility_id())
    AND (SELECT public.current_user_is_clinical_staff())
  );

DROP POLICY IF EXISTS lab_result_attachments_technician_insert ON public.lab_result_attachments;
CREATE POLICY lab_result_attachments_technician_insert
  ON public.lab_result_attachments FOR INSERT TO authenticated
  WITH CHECK (
    facility_id = (SELECT public.current_user_facility_id())
    AND lab_order_id IS NOT NULL
    AND storage_path IS NOT NULL
    AND length(btrim(storage_path)) > 0
    AND file_name IS NOT NULL
    AND length(btrim(file_name)) > 0
    AND mime_type IN ('application/pdf','image/jpeg','image/png')
    AND file_size_bytes BETWEEN 1 AND 15728640
    AND uploaded_by = auth.uid()
    AND (
      (SELECT public.current_user_has_role('admin'::public.app_role))
      OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
      OR (SELECT public.current_user_has_role('lab_technician'::public.app_role))
    )
    AND EXISTS (
      SELECT 1
      FROM public.lab_orders lo
      JOIN public.service_orders so
        ON so.related_entity_id = coalesce(lo.parent_order_id, lo.id)
        AND so.department = 'laboratory'
        AND so.patient_id = lo.patient_id
        AND so.facility_id = lo.facility_id
        AND so.status IN ('released', 'in_progress', 'completed')
      WHERE lo.id = lab_result_attachments.lab_order_id
        AND lo.facility_id = lab_result_attachments.facility_id
    )
  );

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'lab-result-attachments',
  'lab-result-attachments',
  false,
  15728640,
  ARRAY['application/pdf','image/jpeg','image/png']
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 15728640,
    allowed_mime_types = ARRAY['application/pdf','image/jpeg','image/png'];

DROP POLICY IF EXISTS lab_result_attachments_storage_read ON storage.objects;
CREATE POLICY lab_result_attachments_storage_read
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'lab-result-attachments'
    AND EXISTS (
      SELECT 1
      FROM public.lab_orders lo
      WHERE lo.id::text = split_part(name, '/', 1)
        AND lo.facility_id = (SELECT public.current_user_facility_id())
        AND (SELECT public.current_user_is_clinical_staff())
    )
  );

DROP POLICY IF EXISTS lab_result_attachments_storage_insert ON storage.objects;
CREATE POLICY lab_result_attachments_storage_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'lab-result-attachments'
    AND (
      (SELECT public.current_user_has_role('admin'::public.app_role))
      OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
      OR (SELECT public.current_user_has_role('lab_technician'::public.app_role))
    )
    AND EXISTS (
      SELECT 1
      FROM public.lab_orders lo
      JOIN public.service_orders so
        ON so.related_entity_id = coalesce(lo.parent_order_id, lo.id)
        AND so.department = 'laboratory'
        AND so.patient_id = lo.patient_id
        AND so.facility_id = lo.facility_id
        AND so.status IN ('released', 'in_progress', 'completed')
      WHERE lo.id::text = split_part(name, '/', 1)
        AND lo.facility_id = (SELECT public.current_user_facility_id())
    )
  );

CREATE OR REPLACE FUNCTION public.get_laboratory_test_groups(
  _include_inactive boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  result jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility to access laboratory panels'; END IF;
  IF NOT (
    public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin')
    OR public.has_role(uid, 'lab_technician') OR public.has_role(uid, 'practitioner')
    OR public.has_role(uid, 'nurse') OR public.has_role(uid, 'midwife')
    OR public.has_role(uid, 'specialist_nurse')
  ) THEN RAISE EXCEPTION 'Laboratory panel access is not permitted'; END IF;
  IF _include_inactive AND NOT (
    public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin')
    OR (public.has_role(uid, 'lab_technician') AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = uid
        AND (p.department IS NULL OR lower(btrim(p.department)) IN ('laboratory', 'lab'))
    ))
  ) THEN RAISE EXCEPTION 'Laboratory panel administration access is not permitted'; END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(g) ORDER BY g.group_name), '[]'::jsonb)
  INTO result
  FROM (
    SELECT t.id, t.group_name, t.group_code, t.description, t.default_charge, t.is_active,
      coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'id', c.id,
          'test_code', c.test_code,
          'test_name', c.test_name,
          'category', c.category,
          'specimen_type', c.specimen_type,
          'sample_quantity', c.sample_quantity,
          'unit', c.unit,
          'reference_low', c.reference_low,
          'reference_high', c.reference_high,
          'reference_text', c.reference_text,
          'default_charge', c.default_charge,
          'parameters', c.parameters,
          'active', c.active,
          'display_order', i.display_order
        ) ORDER BY i.display_order)
        FROM public.lab_test_group_items i
        JOIN public.lab_test_catalogue c
          ON c.id = i.test_id
          AND (_include_inactive OR c.active)
        WHERE i.group_id = t.id
      ), '[]'::jsonb) AS tests
    FROM public.lab_test_groups t
    WHERE t.facility_id = v_facility
      AND (_include_inactive OR t.is_active)
      AND (_include_inactive OR NOT EXISTS (
        SELECT 1
        FROM public.lab_test_group_items i
        JOIN public.lab_test_catalogue c ON c.id = i.test_id
        WHERE i.group_id = t.id AND NOT c.active
      ))
  ) g;
  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_lab_result_attachments(_lab_order_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  result jsonb;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF v_facility IS NULL THEN
    RAISE EXCEPTION 'Select an active facility to access laboratory report attachments';
  END IF;
  IF NOT (
    public.has_role(uid, 'admin')
    OR public.has_role(uid, 'it_admin')
    OR public.current_user_is_clinical_staff()
  ) THEN
    RAISE EXCEPTION 'Clinical staff or facility administrator access is required for laboratory report attachments';
  END IF;
  IF coalesce(cardinality(_lab_order_ids), 0) > 300 THEN
    RAISE EXCEPTION 'A maximum of 300 laboratory orders may be requested at once';
  END IF;

  SELECT coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'id', attachment.id,
        'lab_order_id', attachment.lab_order_id,
        'storage_path', attachment.storage_path,
        'file_name', attachment.file_name,
        'mime_type', attachment.mime_type,
        'created_at', attachment.created_at
      ) ORDER BY attachment.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO result
  FROM (
    SELECT a.id, a.lab_order_id, a.storage_path, a.file_name, a.mime_type, a.created_at
    FROM public.lab_result_attachments a
    JOIN public.lab_orders lo
      ON lo.id = a.lab_order_id
      AND lo.facility_id = a.facility_id
    JOIN public.patients p
      ON p.id = lo.patient_id
      AND p.facility_id = lo.facility_id
    WHERE a.facility_id = v_facility
      AND a.lab_order_id = ANY(coalesce(_lab_order_ids, ARRAY[]::uuid[]))
      -- Legacy rows with missing or duplicate storage paths are not readable.
      AND a.storage_path IS NOT NULL
      AND a.file_name IS NOT NULL
      AND a.mime_type IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.lab_result_attachments duplicate
        WHERE duplicate.storage_path = a.storage_path
          AND duplicate.id <> a.id
      )
      AND EXISTS (
        SELECT 1
        FROM public.service_orders so
        WHERE so.related_entity_id = coalesce(lo.parent_order_id, lo.id)
          AND so.department = 'laboratory'
          AND so.patient_id = lo.patient_id
          AND so.facility_id = lo.facility_id
          AND so.status IN ('released', 'in_progress', 'completed')
      )
      AND (
        a.lab_result_id IS NULL
        OR EXISTS (
          SELECT 1
          FROM public.lab_results lr
          WHERE lr.id = a.lab_result_id
            AND lr.lab_order_id = lo.id
            AND lr.patient_id = lo.patient_id
            AND lr.facility_id = lo.facility_id
        )
      )
    ORDER BY a.created_at DESC
    LIMIT 1000
  ) attachment;

  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_laboratory_test_groups(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_test_groups(boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.get_lab_result_attachments(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_lab_result_attachments(uuid[]) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
