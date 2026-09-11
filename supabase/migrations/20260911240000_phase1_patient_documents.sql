-- Phase 1: patient document metadata and private storage.
-- The application uploads files to the private patient-documents bucket and records
-- governed metadata in public.patient_documents.

CREATE TABLE IF NOT EXISTS public.patient_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL,
  file_name TEXT NOT NULL,
  storage_path TEXT NOT NULL UNIQUE,
  mime_type TEXT,
  file_size BIGINT,
  notes TEXT,
  uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT patient_documents_file_size_positive CHECK (file_size IS NULL OR file_size > 0)
);

CREATE INDEX IF NOT EXISTS idx_patient_documents_patient_time
  ON public.patient_documents(patient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_patient_documents_type
  ON public.patient_documents(patient_id, document_type);

ALTER TABLE public.patient_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "patients read own documents" ON public.patient_documents;
CREATE POLICY "patients read own documents"
  ON public.patient_documents FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.patients p
      WHERE p.id = patient_documents.patient_id
        AND p.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "staff read patient documents" ON public.patient_documents;
CREATE POLICY "staff read patient documents"
  ON public.patient_documents FOR SELECT
  USING (
    public.is_clinical_staff(auth.uid())
    OR public.has_role(auth.uid(),'accountant')
    OR public.has_role(auth.uid(),'admin')
  );

DROP POLICY IF EXISTS "clinical staff upload patient documents" ON public.patient_documents;
CREATE POLICY "clinical staff upload patient documents"
  ON public.patient_documents FOR INSERT
  WITH CHECK (
    public.is_clinical_staff(auth.uid())
    AND uploaded_by = auth.uid()
  );

DROP POLICY IF EXISTS "admins manage patient documents" ON public.patient_documents;
CREATE POLICY "admins manage patient documents"
  ON public.patient_documents FOR DELETE
  USING (public.has_role(auth.uid(),'admin'));

DROP TRIGGER IF EXISTS t_patient_documents_updated ON public.patient_documents;
CREATE TRIGGER t_patient_documents_updated
BEFORE UPDATE ON public.patient_documents
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Private bucket: files are never publicly readable. Access is controlled by
-- storage object policies and the metadata table policies above.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'patient-documents',
  'patient-documents',
  false,
  10485760,
  ARRAY['application/pdf','image/jpeg','image/png','image/webp','text/plain']::text[]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 10485760,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "patient documents storage read" ON storage.objects;
CREATE POLICY "patient documents storage read"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'patient-documents'
    AND (
      public.is_clinical_staff(auth.uid())
      OR public.has_role(auth.uid(),'accountant')
      OR public.has_role(auth.uid(),'admin')
      OR EXISTS (
        SELECT 1
        FROM public.patient_documents d
        JOIN public.patients p ON p.id = d.patient_id
        WHERE d.storage_path = storage.objects.name
          AND p.user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "patient documents storage upload" ON storage.objects;
CREATE POLICY "patient documents storage upload"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'patient-documents'
    AND public.is_clinical_staff(auth.uid())
  );

DROP POLICY IF EXISTS "patient documents storage delete" ON storage.objects;
CREATE POLICY "patient documents storage delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'patient-documents'
    AND public.has_role(auth.uid(),'admin')
  );

DROP POLICY IF EXISTS "patient documents storage update" ON storage.objects;
CREATE POLICY "patient documents storage update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'patient-documents'
    AND public.has_role(auth.uid(),'admin')
  )
  WITH CHECK (
    bucket_id = 'patient-documents'
    AND public.has_role(auth.uid(),'admin')
  );
