BEGIN;

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

ALTER TABLE public.lab_result_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lab_result_attachments FROM PUBLIC, anon;
GRANT SELECT, INSERT ON TABLE public.lab_result_attachments TO authenticated;

DROP POLICY IF EXISTS lab_result_attachments_facility_read ON public.lab_result_attachments;
CREATE POLICY lab_result_attachments_facility_read
  ON public.lab_result_attachments FOR SELECT TO authenticated
  USING (
    facility_id = (SELECT public.current_user_facility_id())
    AND (SELECT public.current_user_is_clinical_staff())
    AND storage_path LIKE lab_order_id::text || '/%'
    AND EXISTS (
      SELECT 1
      FROM public.lab_orders lo
      JOIN public.patients p
        ON p.id = lo.patient_id
       AND p.facility_id = lo.facility_id
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

DROP POLICY IF EXISTS lab_result_attachments_technician_insert ON public.lab_result_attachments;
CREATE POLICY lab_result_attachments_technician_insert
  ON public.lab_result_attachments FOR INSERT TO authenticated
  WITH CHECK (
    facility_id = (SELECT public.current_user_facility_id())
    AND storage_path LIKE lab_order_id::text || '/%'
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
        AND (
          lab_result_attachments.lab_result_id IS NULL
          OR EXISTS (
            SELECT 1
            FROM public.lab_results lr
            WHERE lr.id = lab_result_attachments.lab_result_id
              AND lr.lab_order_id = lo.id
              AND lr.patient_id = lo.patient_id
              AND lr.facility_id = lo.facility_id
          )
        )
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
      JOIN public.service_orders so
        ON so.related_entity_id = coalesce(lo.parent_order_id, lo.id)
        AND so.department = 'laboratory'
        AND so.patient_id = lo.patient_id
        AND so.facility_id = lo.facility_id
        AND so.status IN ('released', 'in_progress', 'completed')
      JOIN public.patients p
        ON p.id = lo.patient_id
        AND p.facility_id = lo.facility_id
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

NOTIFY pgrst, 'reload schema';
COMMIT;
