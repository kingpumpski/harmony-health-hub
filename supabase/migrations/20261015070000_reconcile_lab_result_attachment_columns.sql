BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.lab_orders') IS NULL
     OR to_regclass('public.lab_results') IS NULL
     OR to_regclass('public.healthcare_facilities') IS NULL
     OR to_regclass('public.patients') IS NULL
     OR to_regclass('public.service_orders') IS NULL
     OR to_regclass('auth.users') IS NULL
  THEN
    RAISE EXCEPTION
      'Cannot reconcile laboratory attachment metadata: required parent tables are missing.';
  END IF;

  IF to_regtype('public.app_role') IS NULL
     OR to_regprocedure('public.current_user_facility_id()') IS NULL
     OR to_regprocedure('public.current_user_is_clinical_staff()') IS NULL
     OR to_regprocedure('public.current_user_has_role(public.app_role)') IS NULL
  THEN
    RAISE EXCEPTION
      'Cannot reconcile laboratory attachment metadata: required authorization objects are missing.';
  END IF;
END;
$preflight$;

CREATE TABLE IF NOT EXISTS public.lab_result_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lab_order_id uuid NOT NULL REFERENCES public.lab_orders(id) ON DELETE CASCADE,
  lab_result_id uuid REFERENCES public.lab_results(id) ON DELETE SET NULL,
  facility_id uuid NOT NULL REFERENCES public.healthcare_facilities(id),
  storage_path text NOT NULL UNIQUE,
  file_name text NOT NULL,
  mime_type text NOT NULL CHECK (mime_type IN ('application/pdf', 'image/jpeg', 'image/png')),
  file_size_bytes bigint NOT NULL CHECK (file_size_bytes BETWEEN 1 AND 15728640),
  uploaded_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

LOCK TABLE public.lab_result_attachments IN ACCESS EXCLUSIVE MODE;

DO $identity$
DECLARE
  v_id_type text;
  v_has_primary_key boolean;
  v_has_id_primary_key boolean;
BEGIN
  SELECT pg_catalog.format_type(a.atttypid, a.atttypmod)
  INTO v_id_type
  FROM pg_catalog.pg_attribute a
  WHERE a.attrelid = 'public.lab_result_attachments'::regclass
    AND a.attname = 'id'
    AND a.attnum > 0
    AND NOT a.attisdropped;

  IF v_id_type IS NULL THEN
    RAISE EXCEPTION
      'Existing laboratory attachment table has no id column; reconcile its primary-key design before proceeding.';
  END IF;

  IF v_id_type <> 'uuid' THEN
    RAISE EXCEPTION
      'Laboratory attachment id must be uuid, but the existing type is %.',
      v_id_type;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lab_result_attachments
    WHERE id IS NULL
  ) OR EXISTS (
    SELECT id
    FROM public.lab_result_attachments
    GROUP BY id
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION
      'Existing laboratory attachment ids contain nulls or duplicates; reconcile them before adding the primary key.';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint c
    WHERE c.conrelid = 'public.lab_result_attachments'::regclass
      AND c.contype = 'p'
  ), EXISTS (
    SELECT 1
    FROM pg_catalog.pg_constraint c
    JOIN pg_catalog.pg_attribute a
      ON a.attrelid = c.conrelid
     AND a.attnum = c.conkey[1]
    WHERE c.conrelid = 'public.lab_result_attachments'::regclass
      AND c.contype = 'p'
      AND cardinality(c.conkey) = 1
      AND a.attname = 'id'
  )
  INTO v_has_primary_key, v_has_id_primary_key;

  IF v_has_primary_key AND NOT v_has_id_primary_key THEN
    RAISE EXCEPTION
      'Existing laboratory attachment table has a primary key other than id; reconcile its key design before proceeding.';
  END IF;

  IF NOT v_has_primary_key THEN
    ALTER TABLE public.lab_result_attachments
      ALTER COLUMN id SET NOT NULL;
    ALTER TABLE public.lab_result_attachments
      ADD CONSTRAINT lab_result_attachments_pkey PRIMARY KEY (id);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = 'public.lab_result_attachments'::regclass
      AND a.attname = 'id'
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND a.atthasdef
  ) THEN
    ALTER TABLE public.lab_result_attachments
      ALTER COLUMN id SET DEFAULT gen_random_uuid();
  END IF;
END;
$identity$;

ALTER TABLE public.lab_result_attachments
  ADD COLUMN IF NOT EXISTS lab_order_id uuid,
  ADD COLUMN IF NOT EXISTS lab_result_id uuid,
  ADD COLUMN IF NOT EXISTS facility_id uuid,
  ADD COLUMN IF NOT EXISTS storage_path text,
  ADD COLUMN IF NOT EXISTS file_name text,
  ADD COLUMN IF NOT EXISTS mime_type text,
  ADD COLUMN IF NOT EXISTS file_size_bytes bigint,
  ADD COLUMN IF NOT EXISTS uploaded_by uuid,
  ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

DO $column_types$
DECLARE
  v_column record;
  v_actual_type text;
BEGIN
  FOR v_column IN
    SELECT *
    FROM (VALUES
      ('lab_order_id', 'uuid'),
      ('lab_result_id', 'uuid'),
      ('facility_id', 'uuid'),
      ('storage_path', 'text'),
      ('file_name', 'text'),
      ('mime_type', 'text'),
      ('file_size_bytes', 'bigint'),
      ('uploaded_by', 'uuid'),
      ('created_at', 'timestamp with time zone')
    ) AS expected(column_name, type_name)
  LOOP
    SELECT pg_catalog.format_type(a.atttypid, a.atttypmod)
    INTO v_actual_type
    FROM pg_catalog.pg_attribute a
    WHERE a.attrelid = 'public.lab_result_attachments'::regclass
      AND a.attname = v_column.column_name
      AND a.attnum > 0
      AND NOT a.attisdropped;

    IF v_actual_type IS DISTINCT FROM v_column.type_name THEN
      RAISE EXCEPTION
        'Laboratory attachment column % must be %, but the existing type is %.',
        v_column.column_name,
        v_column.type_name,
        coalesce(v_actual_type, '<missing>');
    END IF;
  END LOOP;
END;
$column_types$;

DO $reconcile$
DECLARE
  v_missing text[];
BEGIN
  SELECT array_agg(required.column_name ORDER BY required.column_name)
  INTO v_missing
  FROM (VALUES
    ('lab_order_id'),
    ('facility_id'),
    ('storage_path'),
    ('file_name'),
    ('mime_type'),
    ('file_size_bytes'),
    ('uploaded_by'),
    ('created_at')
  ) AS required(column_name)
  WHERE EXISTS (
    SELECT 1
    FROM public.lab_result_attachments a
    WHERE CASE required.column_name
      WHEN 'lab_order_id' THEN a.lab_order_id IS NULL
      WHEN 'facility_id' THEN a.facility_id IS NULL
      WHEN 'storage_path' THEN a.storage_path IS NULL
      WHEN 'file_name' THEN a.file_name IS NULL
      WHEN 'mime_type' THEN a.mime_type IS NULL
      WHEN 'file_size_bytes' THEN a.file_size_bytes IS NULL
      WHEN 'uploaded_by' THEN a.uploaded_by IS NULL
      WHEN 'created_at' THEN a.created_at IS NULL
      ELSE false
    END
  );

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION
      'Laboratory attachment records have missing required metadata: %',
      v_missing
      USING HINT =
        'Map existing values from verified source records. Do not guess clinical lineage or storage metadata, then rerun the migration.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lab_result_attachments
    WHERE file_size_bytes NOT BETWEEN 1 AND 15728640
  ) THEN
    RAISE EXCEPTION
      'Laboratory attachment file sizes must be between 1 and 15728640 bytes.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.lab_result_attachments
    WHERE mime_type NOT IN ('application/pdf', 'image/jpeg', 'image/png')
  ) THEN
    RAISE EXCEPTION
      'Laboratory attachment MIME types must be PDF, JPEG, or PNG.';
  END IF;

  IF EXISTS (
    SELECT storage_path
    FROM public.lab_result_attachments
    GROUP BY storage_path
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION
      'Duplicate laboratory attachment storage paths must be reconciled before enforcing uniqueness.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lab_result_attachments a
    LEFT JOIN public.lab_orders lo ON lo.id = a.lab_order_id
    WHERE lo.id IS NULL
  ) THEN
    RAISE EXCEPTION 'A laboratory attachment references a missing laboratory order.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lab_result_attachments a
    JOIN public.lab_orders lo ON lo.id = a.lab_order_id
    WHERE a.facility_id IS DISTINCT FROM lo.facility_id
  ) THEN
    RAISE EXCEPTION
      'A laboratory attachment facility does not match its laboratory order.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lab_result_attachments a
    LEFT JOIN public.healthcare_facilities f ON f.id = a.facility_id
    WHERE f.id IS NULL
  ) THEN
    RAISE EXCEPTION 'A laboratory attachment references a missing facility.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lab_result_attachments a
    LEFT JOIN auth.users u ON u.id = a.uploaded_by
    WHERE u.id IS NULL
  ) THEN
    RAISE EXCEPTION 'A laboratory attachment references a missing uploader account.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lab_result_attachments a
    JOIN public.lab_orders lo ON lo.id = a.lab_order_id
    LEFT JOIN public.lab_results lr ON lr.id = a.lab_result_id
    WHERE a.lab_result_id IS NOT NULL
      AND (
        lr.id IS NULL
        OR lr.lab_order_id IS DISTINCT FROM lo.id
        OR lr.patient_id IS DISTINCT FROM lo.patient_id
        OR lr.facility_id IS DISTINCT FROM lo.facility_id
      )
  ) THEN
    RAISE EXCEPTION
      'A linked laboratory result does not match its order, patient, or facility.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.lab_result_attachments a
    JOIN public.lab_orders lo ON lo.id = a.lab_order_id
    JOIN public.patients p ON p.id = lo.patient_id
    WHERE p.facility_id IS DISTINCT FROM lo.facility_id
  ) THEN
    RAISE EXCEPTION
      'A laboratory order and its patient have conflicting facility assignments.';
  END IF;
END;
$reconcile$;

ALTER TABLE public.lab_result_attachments
  ALTER COLUMN lab_order_id SET NOT NULL,
  ALTER COLUMN facility_id SET NOT NULL,
  ALTER COLUMN storage_path SET NOT NULL,
  ALTER COLUMN file_name SET NOT NULL,
  ALTER COLUMN mime_type SET NOT NULL,
  ALTER COLUMN file_size_bytes SET NOT NULL,
  ALTER COLUMN uploaded_by SET NOT NULL,
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN created_at SET NOT NULL;

DO $constraints$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.lab_result_attachments'::regclass
      AND conname = 'lab_result_attachments_lab_order_id_fkey'
  ) THEN
    ALTER TABLE public.lab_result_attachments
      ADD CONSTRAINT lab_result_attachments_lab_order_id_fkey
      FOREIGN KEY (lab_order_id)
      REFERENCES public.lab_orders(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.lab_result_attachments'::regclass
      AND conname = 'lab_result_attachments_lab_result_id_fkey'
  ) THEN
    ALTER TABLE public.lab_result_attachments
      ADD CONSTRAINT lab_result_attachments_lab_result_id_fkey
      FOREIGN KEY (lab_result_id)
      REFERENCES public.lab_results(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.lab_result_attachments'::regclass
      AND conname = 'lab_result_attachments_facility_id_fkey'
  ) THEN
    ALTER TABLE public.lab_result_attachments
      ADD CONSTRAINT lab_result_attachments_facility_id_fkey
      FOREIGN KEY (facility_id)
      REFERENCES public.healthcare_facilities(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.lab_result_attachments'::regclass
      AND conname = 'lab_result_attachments_uploaded_by_fkey'
  ) THEN
    ALTER TABLE public.lab_result_attachments
      ADD CONSTRAINT lab_result_attachments_uploaded_by_fkey
      FOREIGN KEY (uploaded_by)
      REFERENCES auth.users(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.lab_result_attachments'::regclass
      AND conname = 'lab_result_attachments_file_size_bytes_check'
  ) THEN
    ALTER TABLE public.lab_result_attachments
      ADD CONSTRAINT lab_result_attachments_file_size_bytes_check
      CHECK (file_size_bytes BETWEEN 1 AND 15728640);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.lab_result_attachments'::regclass
      AND conname = 'lab_result_attachments_mime_type_check'
  ) THEN
    ALTER TABLE public.lab_result_attachments
      ADD CONSTRAINT lab_result_attachments_mime_type_check
      CHECK (mime_type IN ('application/pdf', 'image/jpeg', 'image/png'));
  END IF;
END;
$constraints$;

CREATE INDEX IF NOT EXISTS idx_lab_result_attachments_facility_id
  ON public.lab_result_attachments (facility_id);
CREATE INDEX IF NOT EXISTS idx_lab_result_attachments_lab_order_id
  ON public.lab_result_attachments (lab_order_id);
CREATE INDEX IF NOT EXISTS idx_lab_result_attachments_lab_result_id
  ON public.lab_result_attachments (lab_result_id);

DO $storage_path_index$
DECLARE
  v_storage_path_attnum smallint;
BEGIN
  SELECT a.attnum
  INTO v_storage_path_attnum
  FROM pg_catalog.pg_attribute a
  WHERE a.attrelid = 'public.lab_result_attachments'::regclass
    AND a.attname = 'storage_path'
    AND a.attnum > 0
    AND NOT a.attisdropped;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index i
    WHERE i.indrelid = 'public.lab_result_attachments'::regclass
      AND i.indisunique
      AND i.indisvalid
      AND i.indpred IS NULL
      AND i.indnkeyatts = 1
      AND i.indkey[0] = v_storage_path_attnum
  ) THEN
    CREATE UNIQUE INDEX idx_lab_result_attachments_storage_path_unique
      ON public.lab_result_attachments (storage_path);
  END IF;
END;
$storage_path_index$;

ALTER TABLE public.lab_result_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lab_result_attachments FROM PUBLIC, anon;
GRANT SELECT, INSERT ON TABLE public.lab_result_attachments TO authenticated;

DROP POLICY IF EXISTS lab_result_attachments_facility_read
  ON public.lab_result_attachments;
CREATE POLICY lab_result_attachments_facility_read
  ON public.lab_result_attachments
  FOR SELECT TO authenticated
  USING (
    facility_id = (SELECT public.current_user_facility_id())
    AND (SELECT public.current_user_is_clinical_staff())
  );

DROP POLICY IF EXISTS lab_result_attachments_technician_insert
  ON public.lab_result_attachments;
CREATE POLICY lab_result_attachments_technician_insert
  ON public.lab_result_attachments
  FOR INSERT TO authenticated
  WITH CHECK (
    facility_id = (SELECT public.current_user_facility_id())
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

NOTIFY pgrst, 'reload schema';

COMMIT;
