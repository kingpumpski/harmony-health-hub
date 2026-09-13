-- Reconcile patient registration and document upload requirements for hosted databases.
-- Every statement is idempotent so this can safely follow older partial deployments.

ALTER TABLE public.patients
  ADD COLUMN IF NOT EXISTS membership_type TEXT NOT NULL DEFAULT 'permanent',
  ADD COLUMN IF NOT EXISTS membership_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS registration_reason TEXT,
  ADD COLUMN IF NOT EXISTS insurance_expiry DATE,
  ADD COLUMN IF NOT EXISTS insurance_group_number TEXT;

ALTER TABLE public.patient_documents
  ADD COLUMN IF NOT EXISTS file_name TEXT,
  ADD COLUMN IF NOT EXISTS mime_type TEXT,
  ADD COLUMN IF NOT EXISTS file_size BIGINT,
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_patients_membership_type
  ON public.patients(membership_type, membership_expires_at);

DROP POLICY IF EXISTS "staff create patients" ON public.patients;
CREATE POLICY "staff create patients"
  ON public.patients FOR INSERT TO authenticated
  WITH CHECK (public.can_edit_patient_record(auth.uid()));

DROP POLICY IF EXISTS "authorized staff update patients" ON public.patients;
CREATE POLICY "authorized staff update patients"
  ON public.patients FOR UPDATE TO authenticated
  USING (public.can_edit_patient_record(auth.uid()))
  WITH CHECK (public.can_edit_patient_record(auth.uid()));

DROP POLICY IF EXISTS "clinical staff upload patient documents" ON public.patient_documents;
CREATE POLICY "clinical staff upload patient documents"
  ON public.patient_documents FOR INSERT TO authenticated
  WITH CHECK (
    public.can_edit_patient_record(auth.uid())
    AND uploaded_by = auth.uid()
  );

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'patient-documents',
  'patient-documents',
  false,
  10485760,
  ARRAY['application/pdf','image/jpeg','image/png','image/webp','text/plain']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = EXCLUDED.allowed_mime_types;