-- The patient_documents schema uses storage_path as the canonical private-file reference.
-- Keep the legacy RPC parameter name for frontend compatibility while writing to the
-- actual schema column, and retain its server-side authorization boundary.
CREATE OR REPLACE FUNCTION public.create_patient_document(
  _patient_id uuid,
  _document_type text,
  _file_url text,
  _notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid,'admin')
    OR public.has_role(uid,'practitioner')
    OR public.has_role(uid,'nurse')
    OR public.has_role(uid,'midwife')
    OR public.has_role(uid,'front_desk')
  ) THEN
    RAISE EXCEPTION 'Document creation is not permitted';
  END IF;

  IF _patient_id IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM public.patients
       WHERE id = _patient_id
         AND COALESCE(status,'active') <> 'inactive'
     )
  THEN
    RAISE EXCEPTION 'Patient not found or inactive';
  END IF;

  IF NULLIF(pg_catalog.btrim(_document_type),'') IS NULL THEN
    RAISE EXCEPTION 'Document type is required';
  END IF;

  IF NULLIF(pg_catalog.btrim(_file_url),'') IS NULL THEN
    RAISE EXCEPTION 'Document file reference is required';
  END IF;

  INSERT INTO public.patient_documents(
    patient_id,
    document_type,
    storage_path,
    notes,
    uploaded_by
  )
  VALUES(
    _patient_id,
    pg_catalog.btrim(_document_type),
    pg_catalog.btrim(_file_url),
    NULLIF(pg_catalog.btrim(_notes),''),
    uid
  )
  RETURNING id INTO v_id;

  RETURN pg_catalog.jsonb_build_object('document_id',v_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.create_patient_document(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_document(uuid,text,text,text) TO authenticated;
