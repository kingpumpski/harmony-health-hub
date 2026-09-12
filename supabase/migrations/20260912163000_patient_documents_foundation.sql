-- Patient document foundation.
-- The Patient Hub already exposes a Documents tab and reads public.patient_documents.
-- This migration reconciles the missing relation without changing existing patient workflows.

CREATE TABLE IF NOT EXISTS public.patient_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL DEFAULT 'other',
  title TEXT,
  file_name TEXT,
  file_url TEXT,
  storage_path TEXT,
  description TEXT,
  uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_patient_documents_patient_created
  ON public.patient_documents(patient_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_patient_documents_type
  ON public.patient_documents(document_type);

ALTER TABLE public.patient_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "patient_documents_staff_select" ON public.patient_documents;
CREATE POLICY "patient_documents_staff_select"
  ON public.patient_documents
  FOR SELECT
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR public.has_role(auth.uid(), 'practitioner')
    OR public.has_role(auth.uid(), 'nurse')
    OR public.has_role(auth.uid(), 'midwife')
    OR public.has_role(auth.uid(), 'front_desk')
    OR public.has_role(auth.uid(), 'accountant')
  );

DROP POLICY IF EXISTS "patient_documents_staff_insert" ON public.patient_documents;
CREATE POLICY "patient_documents_staff_insert"
  ON public.patient_documents
  FOR INSERT
  TO authenticated
  WITH CHECK (
    uploaded_by = auth.uid()
    AND (
      public.has_role(auth.uid(), 'admin')
      OR public.has_role(auth.uid(), 'practitioner')
      OR public.has_role(auth.uid(), 'nurse')
      OR public.has_role(auth.uid(), 'midwife')
      OR public.has_role(auth.uid(), 'front_desk')
    )
  );

DROP POLICY IF EXISTS "patient_documents_staff_update" ON public.patient_documents;
CREATE POLICY "patient_documents_staff_update"
  ON public.patient_documents
  FOR UPDATE
  TO authenticated
  USING (
    public.has_role(auth.uid(), 'admin')
    OR uploaded_by = auth.uid()
  )
  WITH CHECK (
    public.has_role(auth.uid(), 'admin')
    OR uploaded_by = auth.uid()
  );

DROP POLICY IF EXISTS "patient_documents_admin_delete" ON public.patient_documents;
CREATE POLICY "patient_documents_admin_delete"
  ON public.patient_documents
  FOR DELETE
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.set_patient_documents_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_patient_documents_updated_at ON public.patient_documents;
CREATE TRIGGER trg_patient_documents_updated_at
  BEFORE UPDATE ON public.patient_documents
  FOR EACH ROW
  EXECUTE FUNCTION public.set_patient_documents_updated_at();

REVOKE ALL ON FUNCTION public.set_patient_documents_updated_at() FROM PUBLIC;
