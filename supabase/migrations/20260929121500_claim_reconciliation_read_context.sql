-- Add a least-privilege read surface for canonical insurer and invoice reconciliation context.
CREATE OR REPLACE FUNCTION public.get_insurance_claim_reconciliation_context(_claim_ids uuid[] DEFAULT NULL)
RETURNS TABLE (
  claim_id uuid,
  invoice_id uuid,
  insurance_company_id uuid,
  insurer_code text,
  insurer_name text,
  invoice_insurance_total numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
BEGIN
  IF uid IS NULL OR NOT (public.has_role(uid,'admin') OR public.has_role(uid,'accountant')) THEN
    RAISE EXCEPTION 'Accounts role required';
  END IF;
  RETURN QUERY
  SELECT
    c.id,
    c.invoice_id,
    coalesce(c.insurance_company_id, p.insurance_company_id, ic.insurance_company_id),
    coalesce(co.code, co2.code),
    coalesce(co.name, co2.name),
    coalesce(sum(greatest(coalesce(ii.insurance_charge,0),0)),0)::numeric
  FROM public.insurance_claims c
  JOIN public.patients p ON p.id=c.patient_id
  LEFT JOIN public.insurance_companies co ON co.id=c.insurance_company_id
  LEFT JOIN LATERAL (
    SELECT x.insurance_company_id
    FROM public.insurance_cases x
    WHERE x.patient_id=c.patient_id AND x.eligibility_status='eligible'
    ORDER BY x.updated_at DESC
    LIMIT 1
  ) ic ON true
  LEFT JOIN public.insurance_companies co2 ON co2.id=coalesce(p.insurance_company_id,ic.insurance_company_id)
  LEFT JOIN public.invoice_items ii ON ii.invoice_id=c.invoice_id
  WHERE p.status <> 'inactive'
    AND (_claim_ids IS NULL OR c.id = ANY(_claim_ids))
  GROUP BY c.id,c.invoice_id,c.insurance_company_id,p.insurance_company_id,ic.insurance_company_id,co.code,co.name,co2.code,co2.name;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_insurance_claim_reconciliation_context(uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_insurance_claim_reconciliation_context(uuid[]) TO authenticated;
