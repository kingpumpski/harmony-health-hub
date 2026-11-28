-- Restore the facility boundary in the SECURITY DEFINER pharmacy workspace.
-- Facility admins remain pharmacy managers inside their selected facility; they
-- are not platform-wide readers of patient, prescription, or dispensing-plan data.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_pharmacy_workspace(_limit integer DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  result jsonb; v_uid uuid := auth.uid(); v_department text;
  v_facility uuid := public.current_user_facility_id();
  v_admin boolean; v_superuser boolean; v_pharmacist boolean; v_front_desk boolean;
  v_catalogue_manager boolean; v_clinical_pharmacy boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  v_admin := public.has_role(v_uid, 'admin');
  v_superuser := public.has_role(v_uid, 'system_superuser');
  v_pharmacist := public.has_role(v_uid, 'pharmacist');
  v_front_desk := public.has_role(v_uid, 'front_desk');
  v_catalogue_manager := public.has_role(v_uid, 'it_admin') OR public.has_role(v_uid, 'system_superuser')
    OR public.current_user_has_catalogue_create_permission('create_items');
  v_clinical_pharmacy := v_admin OR v_pharmacist;
  SELECT NULLIF(pg_catalog.lower(pg_catalog.btrim(p.department)), '') INTO v_department
    FROM public.profiles p WHERE p.id = v_uid;
  IF v_pharmacist AND v_department IS NOT NULL AND v_department <> 'pharmacy' THEN
    RAISE EXCEPTION 'Pharmacy workspace access is not permitted for this department';
  END IF;
  IF v_front_desk AND v_department IS NOT NULL AND v_department NOT IN ('pharmacy', 'front desk', 'front_desk') THEN
    RAISE EXCEPTION 'Pharmacy workspace access is not permitted for this department';
  END IF;
  IF NOT (v_admin OR v_pharmacist OR v_front_desk OR v_catalogue_manager) THEN
    RAISE EXCEPTION 'Pharmacy workspace access is not permitted';
  END IF;
  _limit := LEAST(GREATEST(COALESCE(_limit, 200), 1), 500);
  SELECT pg_catalog.jsonb_build_object(
    'patients', CASE WHEN v_admin OR v_pharmacist OR v_front_desk THEN COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(p) ORDER BY p.first_name, p.last_name)
      FROM (SELECT p.id, p.first_name, p.last_name, p.patient_code
        FROM public.patients p WHERE COALESCE(p.status, 'active') <> 'inactive'
          AND v_facility IS NOT NULL AND p.facility_id = v_facility
        ORDER BY p.first_name, p.last_name LIMIT _limit) p
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'catalogue', CASE WHEN v_catalogue_manager OR v_admin OR v_pharmacist THEN COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(c) ORDER BY c.name)
      FROM (SELECT c.id, c.name, c.category, c.generic_name, c.strength, c.form
        FROM public.medication_catalogue c WHERE c.active
          AND NOT EXISTS (SELECT 1 FROM public.pharmacy_inventory i
            WHERE i.facility_id = v_facility AND i.catalogue_id = c.id AND i.active AND i.batch_number IS NULL)
        ORDER BY c.name LIMIT _limit) c
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'unassigned_inventory', CASE WHEN v_admin OR v_superuser THEN COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.drug_name, i.expiry_date NULLS LAST)
      FROM (SELECT i.id, i.catalogue_id, i.drug_name, i.brand_name, i.generic_name, c.category,
        i.form, i.strength, i.stock_quantity, i.reorder_level, i.unit_price, i.supplier, i.batch_number,
        i.expiry_date, i.barcode, i.nhis_patient_price, i.nhis_claim_amount
        FROM public.pharmacy_inventory i LEFT JOIN public.medication_catalogue c ON c.id = i.catalogue_id
        WHERE i.active AND i.facility_id IS NULL ORDER BY i.drug_name LIMIT _limit) i
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'inventory', COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(i) ORDER BY i.drug_name, i.expiry_date NULLS LAST)
      FROM (SELECT i.id, i.catalogue_id, i.facility_id, i.drug_name, i.brand_name, i.generic_name, c.category,
        i.form, i.strength, i.stock_quantity, i.reorder_level, i.unit_price, i.supplier, i.batch_number,
        i.expiry_date, i.barcode, i.nhis_patient_price, i.nhis_claim_amount
        FROM public.pharmacy_inventory i LEFT JOIN public.medication_catalogue c ON c.id = i.catalogue_id
        WHERE i.active AND i.facility_id = v_facility
          AND (i.expiry_date IS NULL OR i.expiry_date >= CURRENT_DATE)
        ORDER BY i.drug_name LIMIT _limit
      ) i
    ), '[]'::jsonb),
    'prescriptions', CASE WHEN v_clinical_pharmacy THEN COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (SELECT r.id, r.patient_id, r.medication, r.dosage, r.frequency, r.duration,
        r.computed_quantity, r.dispensed_quantity, r.status, r.created_at, r.encounter_id,
        pg_catalog.jsonb_build_object('id', p.id, 'first_name', p.first_name, 'last_name', p.last_name,
          'patient_code', p.patient_code, 'date_of_birth', p.date_of_birth, 'gender', p.gender,
          'blood_group', p.blood_group, 'allergies', p.allergies, 'insurance_provider', p.insurance_provider,
          'insurance_number', p.insurance_number, 'insurance_expiry', p.insurance_expiry) AS patients,
        COALESCE(NULLIF(e.principal_diagnosis, ''), (
          SELECT pg_catalog.string_agg(d.diagnosis, ', ' ORDER BY d.is_principal DESC, d.created_at DESC)
          FROM public.diagnoses d WHERE d.encounter_id = r.encounter_id
        )) AS diagnosis
        FROM public.prescriptions r JOIN public.patients p ON p.id = r.patient_id
        LEFT JOIN public.encounters e ON e.id = r.encounter_id AND e.patient_id = r.patient_id
        WHERE r.status IN ('pending', 'paid')
          AND v_facility IS NOT NULL AND p.facility_id = v_facility
        ORDER BY r.created_at DESC LIMIT _limit) x
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'plans', CASE WHEN v_clinical_pharmacy THEN COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (SELECT d.id, d.patient_id, d.medication_name, d.prepared_quantity, d.service_order_id,
        d.status, d.created_at, d.patient_charge, d.nhis_claim_amount, d.prescription_id, d.inventory_id,
        r.medication AS prescribed_medication, r.dosage, r.frequency, r.duration,
        r.computed_quantity, r.dispensed_quantity, so.status AS service_order_status,
        pg_catalog.jsonb_build_object('id', p.id, 'first_name', p.first_name, 'last_name', p.last_name,
          'patient_code', p.patient_code, 'date_of_birth', p.date_of_birth, 'gender', p.gender,
          'blood_group', p.blood_group, 'allergies', p.allergies, 'insurance_provider', p.insurance_provider,
          'insurance_number', p.insurance_number, 'insurance_expiry', p.insurance_expiry) AS patients,
        COALESCE(NULLIF(e.principal_diagnosis, ''), (
          SELECT pg_catalog.string_agg(dx.diagnosis, ', ' ORDER BY dx.is_principal DESC, dx.created_at DESC)
          FROM public.diagnoses dx WHERE dx.encounter_id = r.encounter_id
        )) AS diagnosis
        FROM public.pharmacy_dispensing_plans d JOIN public.patients p ON p.id = d.patient_id
        LEFT JOIN public.prescriptions r ON r.id = d.prescription_id AND r.patient_id = d.patient_id
        LEFT JOIN public.encounters e ON e.id = r.encounter_id AND e.patient_id = r.patient_id
        LEFT JOIN public.service_orders so ON so.id = d.service_order_id
        WHERE d.status <> 'cancelled'
          AND v_facility IS NOT NULL
          AND d.facility_id = v_facility
          AND p.facility_id = v_facility
        ORDER BY d.created_at DESC LIMIT _limit) x
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    'pos_sales', CASE WHEN v_admin OR v_pharmacist OR v_front_desk THEN COALESCE((
      SELECT pg_catalog.jsonb_agg(pg_catalog.to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (SELECT s.id, s.patient_id, s.medication, s.quantity, s.total_amount, s.status,
        s.service_order_id, s.created_at, COALESCE(so.status, s.status) AS effective_status
        FROM public.pharmacy_pos_sales s LEFT JOIN public.service_orders so ON so.id = s.service_order_id
        WHERE s.status NOT IN ('dispensed', 'cancelled') AND s.facility_id = v_facility
        ORDER BY s.created_at DESC LIMIT _limit) x
    ), '[]'::jsonb) ELSE '[]'::jsonb END
  ) INTO result;
  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_pharmacy_workspace(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pharmacy_workspace(integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
