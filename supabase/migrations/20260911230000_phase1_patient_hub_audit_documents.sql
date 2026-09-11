-- Phase 1: patient record governance, patient hub document metadata and immutable audit trail.
-- Designed around FHIR Patient/Provenance/AuditEvent concepts: stable patient identifiers,
-- actor/timestamp provenance, and append-only change history.

-- Keep patient updates limited to roles that are responsible for registration or clinical care.
CREATE OR REPLACE FUNCTION public.can_edit_patient_record(_user_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role IN ('admin','practitioner','nurse','midwife','front_desk')
  );
$$;

DROP POLICY IF EXISTS "staff update patients" ON public.patients;
CREATE POLICY "authorized staff update patients"
  ON public.patients
  FOR UPDATE
  USING (public.can_edit_patient_record(auth.uid()))
  WITH CHECK (public.can_edit_patient_record(auth.uid()));

-- Append-only patient change history. The application never writes this table directly.
CREATE TABLE IF NOT EXISTS public.patient_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE RESTRICT,
  actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  operation TEXT NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
  changed_fields JSONB NOT NULL DEFAULT '{}'::jsonb,
  old_record JSONB,
  new_record JSONB,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_patient_audit_patient_time
  ON public.patient_audit(patient_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_patient_audit_actor_time
  ON public.patient_audit(actor_user_id, occurred_at DESC);

ALTER TABLE public.patient_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins read patient audit" ON public.patient_audit;
CREATE POLICY "admins read patient audit"
  ON public.patient_audit
  FOR SELECT
  USING (public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.audit_patient_change()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  old_json JSONB;
  new_json JSONB;
  changed JSONB;
BEGIN
  old_json := CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END;
  new_json := CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) ELSE NULL END;

  IF TG_OP = 'UPDATE' THEN
    SELECT COALESCE(
      jsonb_object_agg(
        COALESCE(o.key, n.key),
        jsonb_build_object('old', o.value, 'new', n.value)
      ) FILTER (WHERE o.value IS DISTINCT FROM n.value),
      '{}'::jsonb
    )
    INTO changed
    FROM jsonb_each(old_json) o
    FULL JOIN jsonb_each(new_json) n ON n.key = o.key;
  ELSE
    changed := '{}'::jsonb;
  END IF;

  INSERT INTO public.patient_audit (
    patient_id,
    actor_user_id,
    operation,
    changed_fields,
    old_record,
    new_record
  ) VALUES (
    COALESCE(NEW.id, OLD.id),
    auth.uid(),
    TG_OP,
    changed,
    old_json,
    new_json
  );

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_patient_audit ON public.patients;
CREATE TRIGGER trg_patient_audit
AFTER INSERT OR UPDATE OR DELETE ON public.patients
FOR EACH ROW EXECUTE FUNCTION public.audit_patient_change();

-- Patient document metadata. Binary content is kept in the private Supabase Storage bucket;
-- this table stores the clinical/document reference and provenance.
CREATE TABLE IF NOT EXISTS public.patient_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL DEFAULT 'other',
  file_name TEXT NOT NULL,
  storage_path TEXT,
  mime_type TEXT,
  file_size BIGINT,
  notes TEXT,
  uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_patient_documents_patient_time
  ON public.patient_documents(patient_id, created_at DESC);

ALTER TABLE public.patient_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "staff read patient documents" ON public.patient_documents;
CREATE POLICY "staff read patient documents"
  ON public.patient_documents FOR SELECT
  USING (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'accountant'));

DROP POLICY IF EXISTS "staff manage patient documents" ON public.patient_documents;
CREATE POLICY "staff manage patient documents"
  ON public.patient_documents FOR ALL
  USING (public.can_edit_patient_record(auth.uid()))
  WITH CHECK (public.can_edit_patient_record(auth.uid()));

DROP TRIGGER IF EXISTS t_patient_documents_updated ON public.patient_documents;
CREATE TRIGGER t_patient_documents_updated
BEFORE UPDATE ON public.patient_documents
FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Private storage bucket for patient documents. Files are never public by default.
INSERT INTO storage.buckets (id, name, public)
VALUES ('patient-documents', 'patient-documents', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "clinical staff upload patient documents" ON storage.objects;
CREATE POLICY "clinical staff upload patient documents"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'patient-documents'
    AND public.can_edit_patient_record(auth.uid())
  );

DROP POLICY IF EXISTS "clinical staff read patient documents storage" ON storage.objects;
CREATE POLICY "clinical staff read patient documents storage"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'patient-documents'
    AND (public.is_clinical_staff(auth.uid()) OR public.has_role(auth.uid(),'accountant'))
  );

DROP POLICY IF EXISTS "clinical staff update patient documents storage" ON storage.objects;
CREATE POLICY "clinical staff update patient documents storage"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'patient-documents' AND public.can_edit_patient_record(auth.uid()))
  WITH CHECK (bucket_id = 'patient-documents' AND public.can_edit_patient_record(auth.uid()));

DROP POLICY IF EXISTS "clinical staff delete patient documents storage" ON storage.objects;
CREATE POLICY "clinical staff delete patient documents storage"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'patient-documents' AND public.can_edit_patient_record(auth.uid()));
