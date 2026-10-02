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

