-- Outside-lab document security reconciliation.
-- Browser metadata writes are routed through an audited RPC and the storage bucket is private.

ALTER TABLE public.outside_lab_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "outside lab staff read" ON public.outside_lab_documents;
CREATE POLICY "outside lab staff read" ON public.outside_lab_documents
  FOR SELECT TO authenticated
  USING (
    public.has_role(auth.uid(),'admin') OR
    public.has_role(auth.uid(),'practitioner') OR
    public.has_role(auth.uid(),'nurse') OR
    public.has_role(auth.uid(),'midwife') OR
    public.has_role(auth.uid(),'specialist_nurse') OR
    public.has_role(auth.uid(),'lab_technician') OR
    public.has_role(auth.uid(),'radiologist') OR
    public.has_role(auth.uid(),'ophthalmologist')
  );

DROP POLICY IF EXISTS "outside lab direct insert" ON public.outside_lab_documents;
DROP POLICY IF EXISTS "outside lab direct update" ON public.outside_lab_documents;
DROP POLICY IF EXISTS "outside lab direct delete" ON public.outside_lab_documents;
REVOKE INSERT, UPDATE, DELETE ON public.outside_lab_documents FROM authenticated;
GRANT SELECT ON public.outside_lab_documents TO authenticated;

CREATE OR REPLACE FUNCTION public.register_outside_lab_document(
  _patient_id UUID,
  _document_type TEXT,
  _title TEXT,
  _storage_path TEXT,
  _mime_type TEXT DEFAULT NULL
)
RETURNS public.outside_lab_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc public.outside_lab_documents;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.has_role(auth.uid(),'admin') OR
    public.has_role(auth.uid(),'practitioner') OR
    public.has_role(auth.uid(),'nurse') OR
    public.has_role(auth.uid(),'midwife') OR
    public.has_role(auth.uid(),'specialist_nurse') OR
    public.has_role(auth.uid(),'lab_technician') OR
    public.has_role(auth.uid(),'radiologist') OR
    public.has_role(auth.uid(),'ophthalmologist')
  ) THEN RAISE EXCEPTION 'Outside-lab document upload is not permitted'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id = _patient_id) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;
  IF NULLIF(btrim(_document_type),'') IS NULL THEN RAISE EXCEPTION 'Document type is required'; END IF;
  IF NULLIF(btrim(_storage_path),'') IS NULL OR position('/' IN _storage_path) = 0 THEN
    RAISE EXCEPTION 'Invalid storage path';
  END IF;
  IF split_part(_storage_path,'/',1) <> _patient_id::text THEN
    RAISE EXCEPTION 'Storage path must be scoped to the patient';
  END IF;

  INSERT INTO public.outside_lab_documents (
    patient_id, document_type, title, storage_path, mime_type, uploaded_by
  ) VALUES (
    _patient_id,
    btrim(_document_type),
    COALESCE(NULLIF(btrim(_title),''), 'Outside laboratory document'),
    _storage_path,
    NULLIF(btrim(_mime_type),''),
    auth.uid()
  ) RETURNING * INTO v_doc;

  PERFORM public.record_system_audit(
    'outside_lab_document_uploaded',
    'outside_lab',
    'outside_lab_document',
    v_doc.id,
    'info',
    jsonb_build_object('patient_id',_patient_id,'document_type',_document_type)
  );
  RETURN v_doc;
END;
$$;

REVOKE ALL ON FUNCTION public.register_outside_lab_document(UUID,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_outside_lab_document(UUID,TEXT,TEXT,TEXT,TEXT) TO authenticated;

-- Keep the clinical document bucket private. The application must use authenticated
-- object access rather than public URLs.
INSERT INTO storage.buckets (id, name, public)
VALUES ('outside-lab','outside-lab',false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "outside lab storage upload" ON storage.objects;
CREATE POLICY "outside lab storage upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'outside-lab' AND
    (
      public.has_role(auth.uid(),'admin') OR
      public.has_role(auth.uid(),'practitioner') OR
      public.has_role(auth.uid(),'nurse') OR
      public.has_role(auth.uid(),'midwife') OR
      public.has_role(auth.uid(),'specialist_nurse') OR
      public.has_role(auth.uid(),'lab_technician') OR
      public.has_role(auth.uid(),'radiologist') OR
      public.has_role(auth.uid(),'ophthalmologist')
    ) AND
    split_part(name,'/',1) IN (SELECT id::text FROM public.patients)
  );

DROP POLICY IF EXISTS "outside lab storage read" ON storage.objects;
CREATE POLICY "outside lab storage read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'outside-lab' AND
    (
      public.has_role(auth.uid(),'admin') OR
      public.has_role(auth.uid(),'practitioner') OR
      public.has_role(auth.uid(),'nurse') OR
      public.has_role(auth.uid(),'midwife') OR
      public.has_role(auth.uid(),'specialist_nurse') OR
      public.has_role(auth.uid(),'lab_technician') OR
      public.has_role(auth.uid(),'radiologist') OR
      public.has_role(auth.uid(),'ophthalmologist')
    ) AND
    split_part(name,'/',1) IN (SELECT id::text FROM public.patients)
  );

DROP POLICY IF EXISTS "outside lab storage delete" ON storage.objects;
CREATE POLICY "outside lab storage delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'outside-lab' AND
    (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'practitioner'))
  );
