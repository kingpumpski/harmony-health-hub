BEGIN;

CREATE OR REPLACE FUNCTION public.create_insurance_claim_draft(
  _patient_id uuid,
  _payer_name text DEFAULT NULL,
  _member_number text DEFAULT NULL,
  _amount_claimed numeric DEFAULT 0,
  _invoice_id uuid DEFAULT NULL
)
RETURNS public.insurance_claims
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_claim public.insurance_claims;
  v_invoice uuid := _invoice_id;
  v_company uuid;
  v_company_name text;
  v_payer text := NULLIF(pg_catalog.btrim(_payer_name), '');
BEGIN
  IF uid IS NULL OR NOT (
    public.has_role(uid,'admin'::public.app_role)
    OR public.has_role(uid,'accountant'::public.app_role)
    OR public.has_role(uid,'front_desk'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Insurance claims access required';
  END IF;

  IF _patient_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id=_patient_id
  ) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  IF _amount_claimed IS NULL OR _amount_claimed < 0 THEN
    RAISE EXCEPTION 'Claim amount must be non-negative';
  END IF;

  IF v_invoice IS NULL THEN
    SELECT i.id INTO v_invoice
    FROM public.invoices i
    WHERE i.patient_id=_patient_id
      AND i.status NOT IN ('cancelled')
      AND i.total_amount > 0
    ORDER BY i.created_at DESC
    LIMIT 1;
  END IF;

  IF v_invoice IS NULL THEN
    RAISE EXCEPTION 'An invoice is required before creating an insurance claim';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.invoices
    WHERE id=v_invoice AND patient_id=_patient_id
  ) THEN
    RAISE EXCEPTION 'Invoice does not belong to patient';
  END IF;

  SELECT p.insurance_company_id
    INTO v_company
  FROM public.patients p
  WHERE p.id=_patient_id;

  IF v_company IS NULL THEN
    SELECT x.insurance_company_id
      INTO v_company
    FROM public.insurance_cases x
    WHERE x.patient_id=_patient_id
      AND x.eligibility_status='eligible'
      AND x.insurance_company_id IS NOT NULL
    ORDER BY x.updated_at DESC
    LIMIT 1;
  END IF;

  IF v_company IS NOT NULL THEN
    SELECT c.name INTO v_company_name
    FROM public.insurance_companies c
    WHERE c.id=v_company;

    IF v_company_name IS NOT NULL AND v_payer IS NULL THEN
      v_payer := v_company_name;
    END IF;
  END IF;

  IF v_payer IS NULL THEN
    RAISE EXCEPTION 'Insurance payer is required when no canonical insurer is linked to the patient';
  END IF;

  INSERT INTO public.insurance_claims(
    invoice_id,
    patient_id,
    provider,
    policy_number,
    payer_name,
    member_number,
    insurance_company_id,
    amount_claimed,
    amount_approved,
    amount_paid,
    status,
    notes,
    submitted_at
  ) VALUES (
    v_invoice,
    _patient_id,
    v_payer,
    NULLIF(pg_catalog.btrim(_member_number),''),
    v_payer,
    NULLIF(pg_catalog.btrim(_member_number),''),
    v_company,
    _amount_claimed,
    NULL,
    0,
    'draft',
    NULL,
    now()
  )
  RETURNING * INTO v_claim;

  RETURN v_claim;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_insurance_claim_draft(uuid,text,text,numeric,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_insurance_claim_draft(uuid,text,text,numeric,uuid) TO authenticated;

COMMIT;