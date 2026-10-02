-- Normalize global medication catalogue from facility-owned stock and harden pharmacy workflows.
-- Existing stock rows without trustworthy facility attribution remain unassigned and cannot be dispensed until reviewed.

CREATE TABLE IF NOT EXISTS public.medication_catalogue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(btrim(name)) >= 2),
  category text NOT NULL DEFAULT 'Uncategorized',
  generic_name text,
  strength text,
  form text,
  active boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS medication_catalogue_normalized_unique
  ON public.medication_catalogue (
    lower(btrim(name)),
    lower(btrim(coalesce(generic_name, ''))),
    lower(btrim(coalesce(strength, ''))),
    lower(btrim(coalesce(form, '')))
  );
ALTER TABLE public.medication_catalogue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS medication_catalogue_authenticated_read ON public.medication_catalogue;
CREATE POLICY medication_catalogue_authenticated_read
  ON public.medication_catalogue FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL AND active);
REVOKE ALL ON public.medication_catalogue FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.medication_catalogue TO authenticated;

ALTER TABLE public.pharmacy_inventory
  ADD COLUMN IF NOT EXISTS catalogue_id uuid REFERENCES public.medication_catalogue(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS facility_id uuid REFERENCES public.healthcare_facilities(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS barcode text,
  ADD COLUMN IF NOT EXISTS nhis_patient_price numeric(12,2) NOT NULL DEFAULT 0 CHECK (nhis_patient_price >= 0),
  ADD COLUMN IF NOT EXISTS nhis_claim_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (nhis_claim_amount >= 0);

ALTER TABLE public.prescriptions
  ADD COLUMN IF NOT EXISTS dispensed_quantity integer NOT NULL DEFAULT 0 CHECK (dispensed_quantity >= 0);
ALTER TABLE public.pharmacy_dispensing_plans
  ADD COLUMN IF NOT EXISTS patient_charge numeric(12,2) NOT NULL DEFAULT 0 CHECK (patient_charge >= 0),
  ADD COLUMN IF NOT EXISTS nhis_claim_amount numeric(12,2) NOT NULL DEFAULT 0 CHECK (nhis_claim_amount >= 0);

-- Migrate the existing medication names into the shared catalogue without guessing facility ownership.
INSERT INTO public.medication_catalogue(name, category, generic_name, strength, form)
SELECT DISTINCT ON (
  lower(btrim(i.drug_name)),
  lower(btrim(coalesce(i.generic_name, ''))),
  lower(btrim(coalesce(i.strength, ''))),
  lower(btrim(coalesce(i.form, '')))
) btrim(i.drug_name), 'Uncategorized', NULLIF(btrim(i.generic_name), ''),
  NULLIF(btrim(i.strength), ''), NULLIF(btrim(i.form), '')
FROM public.pharmacy_inventory i
WHERE NULLIF(btrim(i.drug_name), '') IS NOT NULL
ORDER BY lower(btrim(i.drug_name)), lower(btrim(coalesce(i.generic_name, ''))),
  lower(btrim(coalesce(i.strength, ''))), lower(btrim(coalesce(i.form, ''))), i.created_at
ON CONFLICT DO NOTHING;

UPDATE public.pharmacy_inventory i
SET catalogue_id = c.id
FROM public.medication_catalogue c
WHERE i.catalogue_id IS NULL
  AND lower(btrim(i.drug_name)) = lower(btrim(c.name))
  AND lower(btrim(coalesce(i.generic_name, ''))) = lower(btrim(coalesce(c.generic_name, '')))
  AND lower(btrim(coalesce(i.strength, ''))) = lower(btrim(coalesce(c.strength, '')))
  AND lower(btrim(coalesce(i.form, ''))) = lower(btrim(coalesce(c.form, '')));

CREATE INDEX IF NOT EXISTS pharmacy_inventory_facility_active_idx
  ON public.pharmacy_inventory(facility_id, active, drug_name);
CREATE INDEX IF NOT EXISTS pharmacy_inventory_facility_barcode_idx
  ON public.pharmacy_inventory(facility_id, barcode) WHERE barcode IS NOT NULL;
CREATE INDEX IF NOT EXISTS pharmacy_inventory_catalogue_idx
  ON public.pharmacy_inventory(catalogue_id);
CREATE UNIQUE INDEX IF NOT EXISTS pharmacy_inventory_facility_catalogue_base_unique
  ON public.pharmacy_inventory(facility_id, catalogue_id)
  WHERE facility_id IS NOT NULL AND catalogue_id IS NOT NULL AND active AND batch_number IS NULL;

-- Direct reads must be facility-scoped. Catalogue visibility is provided separately by the shared catalogue.
DROP POLICY IF EXISTS inv_clinical_read ON public.pharmacy_inventory;
DROP POLICY IF EXISTS pharmacy_inventory_facility_read ON public.pharmacy_inventory;
CREATE POLICY pharmacy_inventory_facility_read ON public.pharmacy_inventory
  FOR SELECT TO authenticated
  USING (facility_id IS NOT NULL AND private.current_user_can_select_facility_record(facility_id, 'medication_read'));
DROP POLICY IF EXISTS inv_pharma_insert ON public.pharmacy_inventory;
-- Legacy direct-mutation policies are removed; validated RPCs are the only stock write surface.
-- Inventory writes are only permitted through validated, audited RPCs.
REVOKE INSERT, UPDATE, DELETE ON public.pharmacy_inventory FROM PUBLIC, anon, authenticated;

DROP FUNCTION IF EXISTS public.create_pharmacy_inventory_item(text,text,text,text,text,text,text,date,integer,integer,numeric);
DROP FUNCTION IF EXISTS public.create_pharmacy_inventory_item(text,text,text,text,text,text,text,date,integer,integer,numeric,text);

CREATE OR REPLACE FUNCTION public.create_pharmacy_inventory_item(
  _drug_name text, _brand_name text, _generic_name text, _strength text, _form text,
  _supplier text, _batch_number text, _expiry_date date, _stock_quantity integer,
  _reorder_level integer, _unit_price numeric, _category text DEFAULT 'Uncategorized'
)
RETURNS public.pharmacy_inventory
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  result public.pharmacy_inventory;
  v_uid uuid := auth.uid();
  v_facility uuid := public.current_user_facility_id();
  v_catalogue_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT (
    public.has_role(v_uid, 'admin') OR public.has_role(v_uid, 'it_admin')
    OR public.has_role(v_uid, 'system_superuser') OR public.has_role(v_uid, 'pharmacist')
    OR public.current_user_has_catalogue_create_permission('create_items')
  ) THEN RAISE EXCEPTION 'Pharmacy inventory management permission required'; END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before adding medication to the store'; END IF;
  IF pg_catalog.length(pg_catalog.btrim(COALESCE(_drug_name, ''))) < 2 THEN RAISE EXCEPTION 'Drug name must contain at least two characters'; END IF;
  IF COALESCE(_stock_quantity, 0) < 0 OR COALESCE(_reorder_level, 0) < 0 OR COALESCE(_unit_price, 0) < 0 THEN RAISE EXCEPTION 'Inventory values cannot be negative'; END IF;
  IF _expiry_date IS NOT NULL AND _expiry_date < CURRENT_DATE THEN RAISE EXCEPTION 'Expiry date cannot be in the past'; END IF;
  IF COALESCE(_stock_quantity, 0) > 0 AND (_expiry_date IS NULL OR COALESCE(_unit_price, 0) <= 0 OR COALESCE(_reorder_level, 0) <= 0) THEN
    RAISE EXCEPTION 'Expiry date, positive retail price and a configured reorder level are required before stock can be made available';
  END IF;

  INSERT INTO public.medication_catalogue(name, category, generic_name, strength, form, created_by)
  VALUES (pg_catalog.btrim(_drug_name), COALESCE(NULLIF(pg_catalog.btrim(_category), ''), 'Uncategorized'),
    NULLIF(pg_catalog.btrim(_generic_name), ''), NULLIF(pg_catalog.btrim(_strength), ''),
    NULLIF(pg_catalog.btrim(_form), ''), v_uid)
  ON CONFLICT DO NOTHING;

  SELECT c.id INTO v_catalogue_id
  FROM public.medication_catalogue c
  WHERE lower(btrim(c.name)) = lower(btrim(_drug_name))
    AND lower(btrim(coalesce(c.generic_name, ''))) = lower(btrim(coalesce(_generic_name, '')))
    AND lower(btrim(coalesce(c.strength, ''))) = lower(btrim(coalesce(_strength, '')))
    AND lower(btrim(coalesce(c.form, ''))) = lower(btrim(coalesce(_form, '')))
  LIMIT 1;
  IF v_catalogue_id IS NULL THEN RAISE EXCEPTION 'Could not resolve global medication catalogue entry'; END IF;

  INSERT INTO public.pharmacy_inventory(
    catalogue_id, facility_id, drug_name, brand_name, generic_name, strength, form,
    supplier, batch_number, expiry_date, stock_quantity, reorder_level, unit_price,
    nhis_patient_price, nhis_claim_amount, active
  ) VALUES (
    v_catalogue_id, v_facility, pg_catalog.btrim(_drug_name), NULLIF(pg_catalog.btrim(_brand_name), ''),
    NULLIF(pg_catalog.btrim(_generic_name), ''), NULLIF(pg_catalog.btrim(_strength), ''),
    NULLIF(pg_catalog.btrim(_form), ''), NULLIF(pg_catalog.btrim(_supplier), ''),
    NULLIF(pg_catalog.btrim(_batch_number), ''), _expiry_date, COALESCE(_stock_quantity, 0),
    COALESCE(_reorder_level, 0), COALESCE(_unit_price, 0), 0, 0, true
  ) RETURNING * INTO result;

  PERFORM public.record_system_audit('pharmacy_inventory_created', 'pharmacy', 'pharmacy_inventory',
    result.id, 'info', pg_catalog.jsonb_build_object('drug_name', result.drug_name,
    'stock_quantity', result.stock_quantity, 'facility_id', v_facility, 'catalogue_id', v_catalogue_id,
    'actor_id', v_uid));
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'This medication is already in the facility store. Select it and edit the existing stock item.';
END;
$function$;

REVOKE ALL ON FUNCTION public.create_pharmacy_inventory_item(text,text,text,text,text,text,text,date,integer,integer,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_inventory_item(text,text,text,text,text,text,text,date,integer,integer,numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.add_global_medication_to_facility(_catalogue_id uuid)
RETURNS public.pharmacy_inventory
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE c public.medication_catalogue; r public.pharmacy_inventory; uid uuid := auth.uid(); fid uuid := public.current_user_facility_id();
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin')
    OR public.has_role(uid, 'system_superuser') OR public.has_role(uid, 'pharmacist')
    OR public.current_user_has_catalogue_create_permission('create_items')
  ) THEN RAISE EXCEPTION 'Pharmacy inventory management permission required'; END IF;
  IF fid IS NULL THEN RAISE EXCEPTION 'Select an active facility before adding medication to the store'; END IF;
  SELECT * INTO c FROM public.medication_catalogue WHERE id = _catalogue_id AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active global medication was not found'; END IF;
  SELECT * INTO r FROM public.pharmacy_inventory
    WHERE facility_id = fid AND catalogue_id = c.id AND active AND batch_number IS NULL
    LIMIT 1 FOR UPDATE;
  IF FOUND THEN RETURN r; END IF;
  INSERT INTO public.pharmacy_inventory(catalogue_id, facility_id, drug_name, generic_name, strength, form,
    stock_quantity, reorder_level, unit_price, nhis_patient_price, nhis_claim_amount, active)
  VALUES (c.id, fid, c.name, c.generic_name, c.strength, c.form, 0, 0, 0, 0, 0, true)
  RETURNING * INTO r;
  PERFORM public.record_system_audit('pharmacy_catalogue_added_to_facility', 'pharmacy',
    'pharmacy_inventory', r.id, 'info', pg_catalog.jsonb_build_object(
      'catalogue_id', c.id, 'facility_id', fid, 'actor_id', uid));
  RETURN r;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO r FROM public.pharmacy_inventory
    WHERE facility_id = fid AND catalogue_id = _catalogue_id AND active AND batch_number IS NULL LIMIT 1;
  RETURN r;
END;
$function$;
REVOKE ALL ON FUNCTION public.add_global_medication_to_facility(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_global_medication_to_facility(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pharmacy_workspace(_limit integer DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
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
          AND (v_admin OR (v_facility IS NOT NULL AND p.facility_id = v_facility))
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
        ORDER BY i.drug_name LIMIT _limit) i
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
          AND (v_admin OR (v_facility IS NOT NULL AND p.facility_id = v_facility))
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
        WHERE d.status <> 'cancelled' AND (v_admin OR (v_facility IS NOT NULL AND d.facility_id = v_facility))
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

DROP FUNCTION IF EXISTS public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric);
DROP FUNCTION IF EXISTS public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text);
DROP FUNCTION IF EXISTS public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric);
CREATE OR REPLACE FUNCTION public.assign_unattributed_pharmacy_inventory(
  _item_id uuid, _reason text
)
RETURNS public.pharmacy_inventory
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE r public.pharmacy_inventory; uid uuid := auth.uid(); fid uuid := public.current_user_facility_id();
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid, 'admin') OR public.has_role(uid, 'system_superuser')) THEN
    RAISE EXCEPTION 'System administrator authorization is required to assign legacy stock';
  END IF;
  IF fid IS NULL THEN RAISE EXCEPTION 'Select the verified destination facility before assigning legacy stock'; END IF;
  IF pg_catalog.length(pg_catalog.btrim(coalesce(_reason, ''))) < 10 THEN
    RAISE EXCEPTION 'Record the stock reconciliation reason before assigning this item';
  END IF;
  UPDATE public.pharmacy_inventory SET facility_id = fid, updated_at = pg_catalog.now()
  WHERE id = _item_id AND facility_id IS NULL AND active RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unassigned inventory item was not found or has already been assigned'; END IF;
  PERFORM public.record_system_audit('pharmacy_legacy_stock_facility_assigned', 'pharmacy',
    'pharmacy_inventory', r.id, 'warning', pg_catalog.jsonb_build_object(
      'drug_name', r.drug_name, 'facility_id', fid, 'reason', pg_catalog.btrim(_reason), 'actor_id', uid));
  RETURN r;
EXCEPTION WHEN unique_violation THEN
  RAISE EXCEPTION 'This would create a duplicate base catalogue item in the selected facility. Reconcile the existing item and batch records before assigning it.';
END;
$function$;
REVOKE ALL ON FUNCTION public.assign_unattributed_pharmacy_inventory(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_unattributed_pharmacy_inventory(uuid,text) TO authenticated;

CREATE FUNCTION public.update_pharmacy_inventory_item(
  _item_id uuid, _drug_name text, _brand_name text, _generic_name text, _strength text,
  _form text, _supplier text, _batch_number text, _expiry_date date, _stock_quantity integer,
  _reorder_level integer, _unit_price numeric, _barcode text DEFAULT NULL,
  _nhis_patient_price numeric DEFAULT 0, _nhis_claim_amount numeric DEFAULT 0,
  _category text DEFAULT NULL
)
RETURNS public.pharmacy_inventory LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE r public.pharmacy_inventory; v_uid uuid := auth.uid(); v_facility uuid := public.current_user_facility_id();
BEGIN
  IF v_uid IS NULL OR NOT (public.has_role(v_uid, 'admin') OR public.has_role(v_uid, 'it_admin')
    OR public.has_role(v_uid, 'system_superuser') OR public.has_role(v_uid, 'pharmacist')
    OR public.current_user_has_catalogue_create_permission('create_items')) THEN
    RAISE EXCEPTION 'Pharmacy inventory management permission required';
  END IF;
  IF v_facility IS NULL THEN RAISE EXCEPTION 'Select an active facility before updating stock'; END IF;
  IF _item_id IS NULL THEN RAISE EXCEPTION 'Inventory item is required'; END IF;
  IF pg_catalog.length(pg_catalog.btrim(COALESCE(_drug_name, ''))) < 2 THEN RAISE EXCEPTION 'Drug name must contain at least two characters'; END IF;
  IF COALESCE(_stock_quantity, 0) < 0 OR COALESCE(_reorder_level, 0) < 0
    OR COALESCE(_unit_price, 0) < 0 OR COALESCE(_nhis_patient_price, 0) < 0
    OR COALESCE(_nhis_claim_amount, 0) < 0 THEN RAISE EXCEPTION 'Inventory values cannot be negative'; END IF;
  IF _expiry_date IS NOT NULL AND _expiry_date < CURRENT_DATE THEN RAISE EXCEPTION 'Expiry date cannot be in the past'; END IF;
  IF COALESCE(_stock_quantity, 0) > 0 AND (_expiry_date IS NULL OR COALESCE(_unit_price, 0) <= 0 OR COALESCE(_reorder_level, 0) <= 0) THEN
    RAISE EXCEPTION 'Expiry date, positive retail price and a configured reorder level are required before stock can be made available';
  END IF;
  UPDATE public.pharmacy_inventory SET
    brand_name = NULLIF(pg_catalog.btrim(_brand_name), ''),
    supplier = NULLIF(pg_catalog.btrim(_supplier), ''), batch_number = NULLIF(pg_catalog.btrim(_batch_number), ''),
    expiry_date = _expiry_date, stock_quantity = COALESCE(_stock_quantity, 0),
    reorder_level = COALESCE(_reorder_level, 0), unit_price = COALESCE(_unit_price, 0),
    barcode = NULLIF(pg_catalog.btrim(_barcode), ''),
    nhis_patient_price = COALESCE(_nhis_patient_price, 0),
    nhis_claim_amount = COALESCE(_nhis_claim_amount, 0),
    updated_at = pg_catalog.now()
  WHERE id = _item_id AND facility_id = v_facility AND active RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active pharmacy inventory item was not found in the active facility'; END IF;
  IF r.catalogue_id IS NOT NULL AND NULLIF(pg_catalog.btrim(_category), '') IS NOT NULL THEN
    UPDATE public.medication_catalogue SET category = pg_catalog.btrim(_category), updated_at = pg_catalog.now()
    WHERE id = r.catalogue_id;
  END IF;
  PERFORM public.record_system_audit('pharmacy_inventory_updated', 'pharmacy', 'pharmacy_inventory', r.id, 'info',
    pg_catalog.jsonb_build_object('drug_name', r.drug_name, 'stock_quantity', r.stock_quantity,
      'facility_id', v_facility, 'actor_id', v_uid));
  RETURN r;
END;
$function$;
REVOKE ALL ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_pharmacy_inventory_item(uuid,text,text,text,text,text,text,text,date,integer,integer,numeric,text,numeric,numeric,text) TO authenticated;

DROP FUNCTION IF EXISTS public.find_pharmacy_alternatives(text,text);
CREATE FUNCTION public.find_pharmacy_alternatives(_medication text, _strength text DEFAULT NULL)
RETURNS TABLE(id uuid, drug_name text, brand_name text, generic_name text, strength text, form text, supplier text, stock_quantity integer, unit_price numeric, category text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE uid uuid := auth.uid(); fid uuid := public.current_user_facility_id(); source_category text;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin') OR public.has_role(uid, 'pharmacist')) THEN
    RAISE EXCEPTION 'Pharmacist role required to review medication alternatives';
  END IF;
  IF fid IS NULL THEN RAISE EXCEPTION 'Select an active facility before finding alternatives'; END IF;
  SELECT c.category INTO source_category FROM public.medication_catalogue c
  WHERE c.active AND (
    lower(c.name) = lower(btrim(_medication))
    OR lower(btrim(_medication)) LIKE lower(btrim(c.name)) || ' %'
    OR lower(coalesce(c.generic_name, '')) = lower(btrim(_medication))
    OR (NULLIF(btrim(c.generic_name), '') IS NOT NULL AND lower(btrim(_medication)) LIKE lower(btrim(c.generic_name)) || ' %')
  )
  ORDER BY CASE WHEN lower(c.name) = lower(btrim(_medication)) THEN 0 ELSE 1 END LIMIT 1;
  IF source_category IS NULL OR lower(btrim(source_category)) = 'uncategorized' THEN RETURN; END IF;
  RETURN QUERY
  SELECT i.id, i.drug_name, i.brand_name, i.generic_name, i.strength, i.form, i.supplier,
    i.stock_quantity, i.unit_price, c.category
  FROM public.pharmacy_inventory i
  JOIN public.medication_catalogue c ON c.id = i.catalogue_id
  WHERE i.active AND i.facility_id = fid AND i.stock_quantity > 0
    AND (i.expiry_date IS NULL OR i.expiry_date >= CURRENT_DATE)
    AND (_strength IS NULL OR i.strength ILIKE '%' || _strength || '%')
    AND (source_category IS NULL OR lower(c.category) = lower(source_category))
    AND NOT (
      lower(btrim(_medication)) = lower(btrim(i.drug_name))
      OR lower(btrim(_medication)) LIKE lower(btrim(i.drug_name)) || ' %'
      OR (NULLIF(btrim(i.generic_name), '') IS NOT NULL AND (
        lower(btrim(_medication)) = lower(btrim(i.generic_name))
        OR lower(btrim(_medication)) LIKE lower(btrim(i.generic_name)) || ' %'
      ))
    )
  ORDER BY i.stock_quantity DESC, i.drug_name LIMIT 20;
END;
$function$;
REVOKE ALL ON FUNCTION public.find_pharmacy_alternatives(text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.find_pharmacy_alternatives(text,text) TO authenticated;

DROP FUNCTION IF EXISTS public.prepare_pharmacy_dispensing(uuid,uuid,integer,text);
DROP FUNCTION IF EXISTS public.prepare_pharmacy_dispensing(uuid,uuid,integer,text,text);
CREATE FUNCTION public.prepare_pharmacy_dispensing(
  _prescription_id uuid, _inventory_id uuid, _quantity integer, _notes text DEFAULT NULL,
  _alternative_reason text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE
  p public.prescriptions; i public.pharmacy_inventory; existing public.pharmacy_dispensing_plans;
  plan_id uuid; order_id uuid; charge numeric; claim numeric; encounter_status text;
  uid uuid := auth.uid(); pf uuid; remaining integer; is_nhis boolean; is_alternative boolean;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin') OR public.has_role(uid, 'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
  IF _quantity IS NULL OR _quantity <= 0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
  SELECT * INTO p FROM public.prescriptions WHERE id = _prescription_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Prescription not found'; END IF;
  pf := public.assert_patient_facility_context(p.patient_id);
  IF p.facility_id IS NULL OR p.facility_id IS DISTINCT FROM pf THEN RAISE EXCEPTION 'Prescription facility attribution is unresolved or mismatched'; END IF;
  SELECT * INTO i FROM public.pharmacy_inventory WHERE id = _inventory_id AND facility_id = pf FOR UPDATE;
  IF NOT FOUND OR NOT i.active OR (i.expiry_date IS NOT NULL AND i.expiry_date < CURRENT_DATE) THEN RAISE EXCEPTION 'Inventory item is not available at this facility or is expired'; END IF;
  remaining := GREATEST(COALESCE(p.computed_quantity, _quantity) - COALESCE(p.dispensed_quantity, 0), 0);
  IF _quantity > remaining THEN RAISE EXCEPTION 'Dispensing quantity exceeds the remaining prescribed quantity'; END IF;
  IF i.stock_quantity < _quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
  IF i.unit_price <= 0 THEN RAISE EXCEPTION 'Configure a positive retail price before dispensing'; END IF;
  is_alternative := NOT (
    lower(btrim(i.drug_name)) = lower(btrim(p.medication))
    OR lower(btrim(p.medication)) LIKE lower(btrim(i.drug_name)) || ' %'
    OR (NULLIF(btrim(i.generic_name), '') IS NOT NULL AND (
      lower(btrim(i.generic_name)) = lower(btrim(p.medication))
      OR lower(btrim(p.medication)) LIKE lower(btrim(i.generic_name)) || ' %'
    ))
    OR (NULLIF(btrim(i.brand_name), '') IS NOT NULL AND (
      lower(btrim(i.brand_name)) = lower(btrim(p.medication))
      OR lower(btrim(p.medication)) LIKE lower(btrim(i.brand_name)) || ' %'
    ))
  );
  IF is_alternative THEN
    IF NOT (public.has_role(uid, 'admin') OR public.has_role(uid, 'pharmacist')) THEN
      RAISE EXCEPTION 'Only a pharmacist may authorize a medication substitution';
    END IF;
    IF pg_catalog.length(pg_catalog.btrim(coalesce(_alternative_reason, ''))) < 10 THEN
      RAISE EXCEPTION 'Document the prescriber authorization and clinical reason before substituting medication';
    END IF;
  END IF;
  IF p.encounter_id IS NOT NULL THEN
    SELECT status INTO encounter_status FROM public.encounters WHERE id = p.encounter_id;
    IF NOT FOUND OR encounter_status IN ('completed', 'cancelled') THEN RAISE EXCEPTION 'Prescription is linked to a closed or missing encounter'; END IF;
  END IF;
  SELECT * INTO existing FROM public.pharmacy_dispensing_plans
    WHERE prescription_id = p.id AND status = 'unpaid' ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  IF FOUND THEN RETURN pg_catalog.jsonb_build_object('plan_id', existing.id, 'service_order_id', existing.service_order_id,
    'amount', existing.patient_charge, 'nhis_claim_amount', existing.nhis_claim_amount, 'status', 'unpaid', 'existing', true); END IF;
  SELECT (COALESCE(NULLIF(upper(pat.insurance_provider), ''), '') LIKE '%NHIS%'
    AND NULLIF(pat.insurance_number, '') IS NOT NULL
    AND (pat.insurance_expiry IS NULL OR pat.insurance_expiry >= CURRENT_DATE))
  INTO is_nhis FROM public.patients pat WHERE pat.id = p.patient_id;
  charge := CASE WHEN COALESCE(is_nhis, false) THEN COALESCE(i.nhis_patient_price, 0) * _quantity ELSE i.unit_price * _quantity END;
  claim := CASE WHEN COALESCE(is_nhis, false) THEN COALESCE(i.nhis_claim_amount, 0) * _quantity ELSE 0 END;
  INSERT INTO public.pharmacy_dispensing_plans(prescription_id, patient_id, inventory_id, medication_name,
    prescribed_dose, prescribed_frequency, prescribed_duration, computed_quantity, prepared_quantity,
    prepared_by, notes, facility_id, patient_charge, nhis_claim_amount)
  VALUES (p.id, p.patient_id, i.id, i.drug_name, p.dosage, p.frequency, p.duration, p.computed_quantity,
    _quantity, uid, CASE WHEN is_alternative THEN pg_catalog.concat_ws(E'\\n', NULLIF(_notes, ''), 'Substitution: ' || pg_catalog.btrim(_alternative_reason)) ELSE _notes END, pf, charge, claim) RETURNING id INTO plan_id;
  INSERT INTO public.service_orders(patient_id, department, service_name, amount, related_entity_id, status,
    requested_by, order_type, service_code, notes, facility_id)
  VALUES (p.patient_id, 'pharmacy', 'Dispense: ' || i.drug_name, charge, p.id,
    'pending_payment_approval', uid, 'drug', i.id, 'Pharmacy preparation ' || plan_id::text, pf)
  RETURNING id INTO order_id;
  UPDATE public.pharmacy_dispensing_plans SET service_order_id = order_id, updated_at = pg_catalog.now() WHERE id = plan_id;
  IF is_alternative THEN
    PERFORM public.record_system_audit('pharmacy_medication_substitution', 'pharmacy', 'pharmacy_dispensing_plans', plan_id, 'warning',
      pg_catalog.jsonb_build_object('prescription_id', p.id, 'prescribed_medication', p.medication,
        'selected_medication', i.drug_name, 'facility_id', pf, 'authorization_reason', _alternative_reason, 'actor_id', uid));
  END IF;
  RETURN pg_catalog.jsonb_build_object('plan_id', plan_id, 'service_order_id', order_id, 'amount', charge,
    'nhis_claim_amount', claim, 'status', 'unpaid');
END;
$function$;
REVOKE ALL ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_pharmacy_dispense(_plan_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE p public.pharmacy_dispensing_plans; i public.pharmacy_inventory; r public.prescriptions;
  so public.service_orders; uid uuid := auth.uid(); pf uuid; total_quantity integer; next_dispensed integer;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin') OR public.has_role(uid, 'pharmacist')) THEN RAISE EXCEPTION 'Pharmacy role required'; END IF;
  SELECT * INTO p FROM public.pharmacy_dispensing_plans WHERE id = _plan_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Dispensing plan not found'; END IF;
  pf := public.assert_patient_facility_context(p.patient_id);
  IF p.facility_id IS NULL OR p.facility_id IS DISTINCT FROM pf THEN RAISE EXCEPTION 'Dispensing plan facility attribution is unresolved or mismatched'; END IF;
  SELECT * INTO r FROM public.prescriptions WHERE id = p.prescription_id FOR UPDATE;
  IF NOT FOUND OR r.patient_id <> p.patient_id OR r.facility_id IS DISTINCT FROM pf THEN RAISE EXCEPTION 'Prescription facility linkage is invalid'; END IF;
  SELECT * INTO so FROM public.service_orders WHERE id = p.service_order_id FOR UPDATE;
  IF NOT FOUND OR so.patient_id <> p.patient_id OR so.related_entity_id <> p.prescription_id OR so.facility_id IS DISTINCT FROM pf THEN RAISE EXCEPTION 'Dispensing service order facility linkage is invalid'; END IF;
  SELECT * INTO i FROM public.pharmacy_inventory WHERE id = p.inventory_id AND facility_id = pf FOR UPDATE;
  IF NOT FOUND OR NOT i.active OR (i.expiry_date IS NOT NULL AND i.expiry_date < CURRENT_DATE) OR i.stock_quantity < p.prepared_quantity THEN
    RAISE EXCEPTION 'Insufficient, expired or unavailable facility stock';
  END IF;
  IF p.status <> 'unpaid' THEN RAISE EXCEPTION 'Dispensing plan is already processed'; END IF;
  IF so.status NOT IN ('released', 'in_progress') THEN RAISE EXCEPTION 'Payment has not been received or the pharmacy order has not been released'; END IF;
  UPDATE public.pharmacy_inventory SET stock_quantity = stock_quantity - p.prepared_quantity, updated_at = pg_catalog.now() WHERE id = i.id;
  total_quantity := COALESCE(r.computed_quantity, p.prepared_quantity);
  next_dispensed := COALESCE(r.dispensed_quantity, 0) + p.prepared_quantity;
  UPDATE public.pharmacy_dispensing_plans SET status = 'dispensed', dispensed_by = uid,
    dispensed_at = pg_catalog.now(), updated_at = pg_catalog.now() WHERE id = p.id;
  UPDATE public.prescriptions SET dispensed_quantity = next_dispensed,
    status = CASE WHEN next_dispensed >= total_quantity THEN 'dispensed' ELSE 'pending' END,
    dispensed_by = CASE WHEN next_dispensed >= total_quantity THEN uid ELSE NULL END,
    dispensed_at = CASE WHEN next_dispensed >= total_quantity THEN pg_catalog.now() ELSE NULL END,
    updated_at = pg_catalog.now()
  WHERE id = r.id AND status IN ('pending', 'paid');
  UPDATE public.service_orders SET status = 'completed', completed_at = COALESCE(completed_at, pg_catalog.now()),
    updated_at = pg_catalog.now() WHERE id = so.id AND status IN ('released', 'in_progress');
  RETURN pg_catalog.jsonb_build_object('plan_id', p.id, 'status', 'dispensed', 'dispensed_quantity', next_dispensed,
    'remaining_quantity', GREATEST(total_quantity - next_dispensed, 0), 'patient_charge', p.patient_charge,
    'nhis_claim_amount', p.nhis_claim_amount, 'dispensed_by', uid);
END;
$function$;
REVOKE ALL ON FUNCTION public.confirm_pharmacy_dispense(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_dispense(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_pharmacy_pos_sale(_patient_id uuid, _inventory_id uuid, _quantity integer)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE result public.pharmacy_pos_sales; item public.pharmacy_inventory; order_id uuid;
  patient_uuid uuid; uid uuid := auth.uid(); fid uuid := public.current_user_facility_id();
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid, 'admin') OR public.has_role(uid, 'pharmacist') OR public.has_role(uid, 'front_desk')) THEN
    RAISE EXCEPTION 'Pharmacy or front desk role required';
  END IF;
  IF fid IS NULL THEN RAISE EXCEPTION 'Select an active facility before creating a POS sale'; END IF;
  IF _quantity IS NULL OR _quantity <= 0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
  SELECT * INTO item FROM public.pharmacy_inventory WHERE id = _inventory_id AND facility_id = fid AND active FOR UPDATE;
  IF NOT FOUND OR item.stock_quantity < _quantity OR (item.expiry_date IS NOT NULL AND item.expiry_date < CURRENT_DATE) THEN
    RAISE EXCEPTION 'Insufficient, expired or unavailable facility stock';
  END IF;
  patient_uuid := _patient_id;
  IF patient_uuid IS NULL THEN
    INSERT INTO public.patients(patient_code, first_name, last_name, status, created_by, facility_id)
    VALUES (NULL, 'Walk-in', 'Pharmacy', 'active', uid, fid) RETURNING id INTO patient_uuid;
  ELSE
    PERFORM public.assert_patient_facility_context(patient_uuid);
  END IF;
  INSERT INTO public.pharmacy_pos_sales(patient_id, medication, inventory_id, quantity, unit_price, created_by, facility_id)
  VALUES (patient_uuid, item.drug_name, item.id, _quantity, item.unit_price, uid, fid) RETURNING * INTO result;
  INSERT INTO public.service_orders(patient_id, department, service_name, amount, related_entity_id, status,
    requested_by, order_type, service_code, notes, facility_id)
  VALUES (patient_uuid, 'pharmacy', 'Walk-in: ' || item.drug_name, item.unit_price * _quantity,
    result.id, 'pending_payment_approval', uid, 'drug', item.id, 'POS sale ' || result.id::text, fid)
  RETURNING id INTO order_id;
  UPDATE public.pharmacy_pos_sales SET service_order_id = order_id WHERE id = result.id RETURNING * INTO result;
  RETURN result;
END;
$function$;
REVOKE ALL ON FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_pharmacy_pos_sale(uuid,uuid,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.confirm_pharmacy_pos_sale(_sale_id uuid)
RETURNS public.pharmacy_pos_sales LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE result public.pharmacy_pos_sales; item public.pharmacy_inventory; uid uuid := auth.uid(); fid uuid := public.current_user_facility_id();
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid, 'admin') OR public.has_role(uid, 'it_admin') OR public.has_role(uid, 'pharmacist')) THEN RAISE EXCEPTION 'Pharmacist role required'; END IF;
  SELECT * INTO result FROM public.pharmacy_pos_sales WHERE id = _sale_id AND facility_id = fid FOR UPDATE;
  IF NOT FOUND OR result.status <> 'awaiting_payment' THEN RAISE EXCEPTION 'POS sale is not awaiting payment in the active facility'; END IF;
  IF result.service_order_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.service_orders WHERE id = result.service_order_id
    AND facility_id = fid AND status IN ('released', 'in_progress')) THEN RAISE EXCEPTION 'Payment has not been received or the order is not released'; END IF;
  SELECT * INTO item FROM public.pharmacy_inventory WHERE id = result.inventory_id AND facility_id = fid FOR UPDATE;
  IF NOT FOUND OR NOT item.active OR (item.expiry_date IS NOT NULL AND item.expiry_date < CURRENT_DATE) OR item.stock_quantity < result.quantity THEN
    RAISE EXCEPTION 'Insufficient, expired or unavailable stock at dispensing time';
  END IF;
  UPDATE public.pharmacy_inventory SET stock_quantity = stock_quantity - result.quantity, updated_at = pg_catalog.now() WHERE id = item.id;
  UPDATE public.pharmacy_pos_sales SET status = 'dispensed', dispensed_by = uid, dispensed_at = pg_catalog.now()
    WHERE id = result.id RETURNING * INTO result;
  RETURN result;
END;
$function$;
REVOKE ALL ON FUNCTION public.confirm_pharmacy_pos_sale(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_pos_sale(uuid) TO authenticated;

