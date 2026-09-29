-- Restore least-privilege patient-directory lookup for radiology technicians.
CREATE OR REPLACE FUNCTION public.search_patient_directory(
  _query text DEFAULT NULL,
  _limit integer DEFAULT 300
)
RETURNS TABLE (id uuid, patient_code text, first_name text, last_name text, phone text, ghana_card_number text, status text, insurance_provider text, insurance_number text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE
  q text := NULLIF(trim(coalesce(_query, '')), '');
  lim integer := least(greatest(coalesce(_limit, 100), 1), 1000);
  can_sensitive boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'practitioner'::app_role)
    OR has_role(auth.uid(), 'nurse'::app_role) OR has_role(auth.uid(), 'midwife'::app_role)
    OR has_role(auth.uid(), 'specialist_nurse'::app_role) OR has_role(auth.uid(), 'lab_technician'::app_role)
    OR has_role(auth.uid(), 'radiologist'::app_role) OR has_role(auth.uid(), 'radiology_technician'::app_role)
    OR has_role(auth.uid(), 'pharmacist'::app_role) OR has_role(auth.uid(), 'accountant'::app_role)
    OR has_role(auth.uid(), 'front_desk'::app_role) OR has_role(auth.uid(), 'canteen'::app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to access the staff patient directory'; END IF;
  can_sensitive := has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'practitioner'::app_role)
    OR has_role(auth.uid(), 'nurse'::app_role) OR has_role(auth.uid(), 'midwife'::app_role)
    OR has_role(auth.uid(), 'specialist_nurse'::app_role) OR has_role(auth.uid(), 'accountant'::app_role)
    OR has_role(auth.uid(), 'front_desk'::app_role);
  RETURN QUERY
  SELECT p.id, p.patient_code, p.first_name, p.last_name, p.phone,
    CASE WHEN can_sensitive THEN p.ghana_card_number ELSE NULL END, p.status::text,
    CASE WHEN can_sensitive THEN p.insurance_provider ELSE NULL END,
    CASE WHEN can_sensitive THEN p.insurance_number ELSE NULL END
  FROM public.patients p
  WHERE q IS NULL OR p.patient_code ILIKE '%' || q || '%' OR p.first_name ILIKE '%' || q || '%'
    OR p.last_name ILIKE '%' || q || '%' OR p.phone ILIKE '%' || q || '%'
    OR p.ghana_card_number ILIKE '%' || q || '%' OR p.email ILIKE '%' || q || '%'
  ORDER BY p.created_at DESC LIMIT lim;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_patient_directory_record(_patient_id uuid)
RETURNS TABLE (id uuid, patient_code text, first_name text, last_name text, phone text, ghana_card_number text, status text, insurance_provider text, insurance_number text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
DECLARE can_sensitive boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'practitioner'::app_role)
    OR has_role(auth.uid(), 'nurse'::app_role) OR has_role(auth.uid(), 'midwife'::app_role)
    OR has_role(auth.uid(), 'specialist_nurse'::app_role) OR has_role(auth.uid(), 'lab_technician'::app_role)
    OR has_role(auth.uid(), 'radiologist'::app_role) OR has_role(auth.uid(), 'radiology_technician'::app_role)
    OR has_role(auth.uid(), 'pharmacist'::app_role) OR has_role(auth.uid(), 'accountant'::app_role)
    OR has_role(auth.uid(), 'front_desk'::app_role) OR has_role(auth.uid(), 'canteen'::app_role)
  ) THEN RAISE EXCEPTION 'Not authorized to access the staff patient directory'; END IF;
  can_sensitive := has_role(auth.uid(), 'admin'::app_role) OR has_role(auth.uid(), 'practitioner'::app_role)
    OR has_role(auth.uid(), 'nurse'::app_role) OR has_role(auth.uid(), 'midwife'::app_role)
    OR has_role(auth.uid(), 'specialist_nurse'::app_role) OR has_role(auth.uid(), 'accountant'::app_role)
    OR has_role(auth.uid(), 'front_desk'::app_role);
  RETURN QUERY SELECT p.id, p.patient_code, p.first_name, p.last_name, p.phone,
    CASE WHEN can_sensitive THEN p.ghana_card_number ELSE NULL END, p.status::text,
    CASE WHEN can_sensitive THEN p.insurance_provider ELSE NULL END,
    CASE WHEN can_sensitive THEN p.insurance_number ELSE NULL END
  FROM public.patients p WHERE p.id = _patient_id;
END;
$$;

REVOKE ALL ON FUNCTION public.search_patient_directory(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_patient_directory_record(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_patient_directory(text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_patient_directory_record(uuid) TO authenticated;