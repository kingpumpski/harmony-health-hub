-- Facility-scoped finance summary for the Billing workspace.
-- No client-side aggregate query bypasses RLS; the SECURITY DEFINER RPC enforces role and facility context.
CREATE OR REPLACE FUNCTION public.get_billing_workspace_summary()
RETURNS TABLE (
  nhis_pending_count bigint,
  cash_collected_today numeric,
  currency text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  uid uuid := auth.uid();
  active_facility uuid := public.current_user_facility_id();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role(uid, 'admin'::public.app_role)
    OR public.has_role(uid, 'accountant'::public.app_role)
    OR public.has_role(uid, 'front_desk'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Billing summary access is not permitted';
  END IF;

  IF active_facility IS NULL THEN
    RAISE EXCEPTION 'Select an active facility before viewing billing summaries';
  END IF;

  RETURN QUERY
  SELECT
    (
      SELECT count(*)::bigint
      FROM public.insurance_claims c
      LEFT JOIN public.insurance_companies ic ON ic.id = c.insurance_company_id
      WHERE c.facility_id = active_facility
        AND c.status IN ('draft', 'submitted', 'acknowledged', 'under_review', 'partially_approved', 'resubmission_required')
        AND (
          lower(pg_catalog.concat_ws(' ', c.payer_name, ic.name, ic.short_name, ic.code)) LIKE '%nhis%'
          OR lower(pg_catalog.concat_ws(' ', c.payer_name, ic.name, ic.short_name, ic.code)) LIKE '%national health insurance%'
        )
    ),
    (
      SELECT coalesce(sum(p.amount), 0)::numeric
      FROM public.payments p
      WHERE p.facility_id = active_facility
        AND p.status = 'completed'
        AND lower(coalesce(p.payment_method, p.method, '')) = 'cash'
        AND p.paid_at >= pg_catalog.date_trunc('day', pg_catalog.now())
        AND p.paid_at < pg_catalog.date_trunc('day', pg_catalog.now()) + interval '1 day'
    ),
    'GHS'::text;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_billing_workspace_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_billing_workspace_summary() TO authenticated;

NOTIFY pgrst, 'reload schema';
