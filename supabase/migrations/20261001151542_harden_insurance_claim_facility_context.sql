-- Restore repository parity for insurance claim facility attribution.
CREATE OR REPLACE FUNCTION public.create_insurance_claim_draft(_patient_id uuid, _payer_name text DEFAULT NULL::text, _member_number text DEFAULT NULL::text, _amount_claimed numeric DEFAULT 0, _invoice_id uuid DEFAULT NULL::uuid)
RETURNS public.insurance_claims
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_claim public.insurance_claims;
  v_invoice uuid := _invoice_id;
  v_company uuid;
  v_company_name text;
  v_payer text := NULLIF(btrim(_payer_name),'');
  v_facility uuid;
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'accountant') OR public.has_role(uid,'front_desk')) THEN
    RAISE EXCEPTION 'Insurance claims access required';
  END IF;
  v_facility := public.assert_patient_facility_context(_patient_id);
  IF _amount_claimed IS NULL OR _amount_claimed < 0 THEN RAISE EXCEPTION 'Claim amount must be non-negative'; END IF;
  IF v_invoice IS NULL THEN
    SELECT i.id INTO v_invoice FROM public.invoices i
    WHERE i.patient_id=_patient_id AND i.facility_id=v_facility AND i.status NOT IN ('cancelled') AND i.total_amount>0
    ORDER BY i.created_at DESC LIMIT 1;
  END IF;
  IF v_invoice IS NULL THEN RAISE EXCEPTION 'An invoice is required before creating an insurance claim'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.invoices WHERE id=v_invoice AND patient_id=_patient_id AND facility_id=v_facility) THEN
    RAISE EXCEPTION 'Invoice does not belong to the patient facility';
  END IF;
  SELECT p.insurance_company_id INTO v_company FROM public.patients p WHERE p.id=_patient_id;
  IF v_company IS NULL THEN
    SELECT x.insurance_company_id INTO v_company FROM public.insurance_cases x
    WHERE x.patient_id=_patient_id AND x.facility_id=v_facility AND x.eligibility_status='eligible' AND x.insurance_company_id IS NOT NULL
    ORDER BY x.updated_at DESC LIMIT 1;
  END IF;
  IF v_company IS NOT NULL THEN
    SELECT c.name INTO v_company_name FROM public.insurance_companies c WHERE c.id=v_company;
    IF v_company_name IS NOT NULL AND v_payer IS NULL THEN v_payer:=v_company_name; END IF;
  END IF;
  IF v_payer IS NULL THEN RAISE EXCEPTION 'Insurance payer is required when no canonical insurer is linked to the patient'; END IF;
  INSERT INTO public.insurance_claims(invoice_id,patient_id,facility_id,provider,policy_number,payer_name,member_number,insurance_company_id,amount_claimed,amount_approved,amount_paid,status,notes,submitted_at)
  VALUES(v_invoice,_patient_id,v_facility,v_payer,NULLIF(btrim(_member_number),''),v_payer,NULLIF(btrim(_member_number),''),v_company,_amount_claimed,NULL,0,'draft',NULL,now())
  RETURNING * INTO v_claim;
  PERFORM public.record_system_audit('insurance_claim_draft_created','insurance','insurance_claim',v_claim.id,'info',jsonb_build_object('patient_id',_patient_id,'invoice_id',v_invoice,'facility_id',v_facility,'amount_claimed',_amount_claimed));
  RETURN v_claim;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_insurance_claim_draft(uuid,text,text,numeric,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_insurance_claim_draft(uuid,text,text,numeric,uuid) TO authenticated;
