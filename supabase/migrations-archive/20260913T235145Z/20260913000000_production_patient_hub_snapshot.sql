-- Production Patient Hub reconciliation.
-- Adds a role-aware, server-authoritative snapshot without replacing existing tables.
-- This is additive and intentionally does not revoke legacy UI writes yet.

CREATE OR REPLACE FUNCTION public.get_patient_hub_snapshot(_patient_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result JSONB;
  is_clinical BOOLEAN;
  is_billing BOOLEAN;
  is_front_desk BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = _patient_id
  ) THEN
    RAISE EXCEPTION 'Patient does not exist';
  END IF;

  is_clinical :=
    public.has_role(auth.uid(), 'admin') OR
    public.has_role(auth.uid(), 'practitioner') OR
    public.has_role(auth.uid(), 'nurse') OR
    public.has_role(auth.uid(), 'midwife') OR
    public.has_role(auth.uid(), 'specialist_nurse') OR
    public.has_role(auth.uid(), 'pharmacist') OR
    public.has_role(auth.uid(), 'lab_technician');

  is_billing :=
    public.has_role(auth.uid(), 'admin') OR
    public.has_role(auth.uid(), 'accountant');

  is_front_desk :=
    public.has_role(auth.uid(), 'admin') OR
    public.has_role(auth.uid(), 'front_desk');

  SELECT jsonb_build_object(
    'patient', to_jsonb(p),
    'appointments', CASE WHEN is_clinical OR is_front_desk THEN COALESCE((
      SELECT jsonb_agg(to_jsonb(a) ORDER BY a.scheduled_at DESC)
      FROM public.appointments a WHERE a.patient_id = _patient_id
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'vitals', CASE WHEN is_clinical THEN COALESCE((
      SELECT jsonb_agg(to_jsonb(v) ORDER BY v.recorded_at DESC)
      FROM public.vital_signs v WHERE v.patient_id = _patient_id
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'encounters', CASE WHEN is_clinical THEN COALESCE((
      SELECT jsonb_agg(to_jsonb(e) ORDER BY e.created_at DESC)
      FROM public.encounters e WHERE e.patient_id = _patient_id
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'labs', CASE WHEN is_clinical THEN COALESCE((
      SELECT jsonb_agg(to_jsonb(l) ORDER BY l.created_at DESC)
      FROM public.lab_orders l WHERE l.patient_id = _patient_id
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'prescriptions', CASE WHEN is_clinical THEN COALESCE((
      SELECT jsonb_agg(to_jsonb(rx) ORDER BY rx.created_at DESC)
      FROM public.prescriptions rx WHERE rx.patient_id = _patient_id
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'invoices', CASE WHEN is_billing OR is_front_desk THEN COALESCE((
      SELECT jsonb_agg(to_jsonb(i) ORDER BY i.created_at DESC)
      FROM public.invoices i WHERE i.patient_id = _patient_id
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'documents', CASE WHEN is_clinical OR is_front_desk THEN COALESCE((
      SELECT jsonb_agg(to_jsonb(d) ORDER BY d.created_at DESC)
      FROM public.patient_documents d WHERE d.patient_id = _patient_id
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'admissions', CASE WHEN is_clinical THEN COALESCE((
      SELECT jsonb_agg(to_jsonb(ad) ORDER BY ad.admitted_at DESC)
      FROM public.admissions ad WHERE ad.patient_id = _patient_id
    ), '[]'::jsonb) ELSE '[]'::jsonb END
  ) INTO result
  FROM public.patients p
  WHERE p.id = _patient_id;

  RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_patient_hub_snapshot(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_patient_hub_snapshot(UUID) TO authenticated;

COMMENT ON FUNCTION public.get_patient_hub_snapshot(UUID) IS
'Role-aware Patient Hub snapshot. Clinical history is never returned to billing/front-desk users.';

-- Keep the audit surface aligned with the operational modules already hardened.
DO $$
DECLARE
  table_name TEXT;
  trigger_name TEXT;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'appointments',
    'vital_signs',
    'encounters',
    'lab_orders',
    'prescriptions',
    'invoices',
    'admissions',
    'patient_documents',
    'service_orders',
    'billing_item_payments'
  ] LOOP
    IF to_regclass('public.' || table_name) IS NOT NULL
       AND to_regprocedure('public.audit_clinical_record_change()') IS NOT NULL THEN
      trigger_name := 'trg_audit_' || table_name || '_production_changes';
      EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', trigger_name, table_name);
      EXECUTE format(
        'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.audit_clinical_record_change()',
        trigger_name,
        table_name
      );
    END IF;
  END LOOP;
END;
$$;
