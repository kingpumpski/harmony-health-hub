BEGIN;
ALTER TABLE public.insurance_service_tariffs
  DROP CONSTRAINT IF EXISTS insurance_service_tariffs_amounts_nonnegative;
ALTER TABLE public.insurance_service_tariffs
  ADD CONSTRAINT insurance_service_tariffs_amounts_nonnegative
  CHECK (base_charge >= 0 AND insurance_charge >= 0 AND top_up >= 0);
ALTER TABLE public.insurance_service_tariffs
  DROP CONSTRAINT IF EXISTS insurance_service_tariffs_effective_dates;
ALTER TABLE public.insurance_service_tariffs
  ADD CONSTRAINT insurance_service_tariffs_effective_dates
  CHECK (effective_to IS NULL OR effective_to >= effective_from);
CREATE INDEX IF NOT EXISTS idx_insurance_service_tariffs_company_service_active
  ON public.insurance_service_tariffs(insurance_company_id, service_code, active);
CREATE INDEX IF NOT EXISTS idx_insurance_service_tariffs_effective_window
  ON public.insurance_service_tariffs(insurance_company_id, service_code, effective_from, effective_to);

CREATE OR REPLACE FUNCTION public.create_insurance_service_tariff(
  _insurance_company_id uuid,
  _service_code text,
  _service_name text,
  _base_charge numeric,
  _insurance_charge numeric,
  _top_up numeric,
  _effective_from date,
  _effective_to date DEFAULT NULL
)
RETURNS public.insurance_service_tariffs
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE r public.insurance_service_tariffs; uid uuid:=auth.uid();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'accountant')) THEN RAISE EXCEPTION 'Tariff configuration privilege required'; END IF;
 IF _insurance_company_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.insurance_companies WHERE id=_insurance_company_id AND active) THEN RAISE EXCEPTION 'Active insurance company is required'; END IF;
 IF length(pg_catalog.btrim(coalesce(_service_code,'')))<2 THEN RAISE EXCEPTION 'Service code is required'; END IF;
 IF _effective_from IS NULL THEN RAISE EXCEPTION 'Effective-from date is required'; END IF;
 IF coalesce(_base_charge,0)<0 OR coalesce(_insurance_charge,0)<0 OR coalesce(_top_up,0)<0 THEN RAISE EXCEPTION 'Tariff amounts cannot be negative'; END IF;
 IF _effective_to IS NOT NULL AND _effective_to < _effective_from THEN RAISE EXCEPTION 'Effective-to date cannot precede effective-from date'; END IF;
 IF EXISTS (
   SELECT 1 FROM public.insurance_service_tariffs t
   WHERE t.insurance_company_id=_insurance_company_id AND t.service_code=upper(pg_catalog.btrim(_service_code))
     AND t.active AND t.effective_from <= coalesce(_effective_to,'9999-12-31'::date)
     AND coalesce(t.effective_to,'9999-12-31'::date) >= _effective_from
 ) THEN RAISE EXCEPTION 'An active tariff already overlaps this service and effective period'; END IF;
 INSERT INTO public.insurance_service_tariffs(payer_name,insurance_company_id,service_code,service_name,base_charge,insurance_charge,top_up,effective_from,effective_to,active,created_by)
 VALUES((SELECT name FROM public.insurance_companies WHERE id=_insurance_company_id),_insurance_company_id,upper(pg_catalog.btrim(_service_code)),NULLIF(pg_catalog.btrim(_service_name),''),coalesce(_base_charge,0),coalesce(_insurance_charge,0),coalesce(_top_up,0),_effective_from,_effective_to,true,uid)
 RETURNING * INTO r;
 PERFORM public.record_system_audit('insurance_tariff_created','billing','insurance_service_tariffs',r.id,'info',jsonb_build_object('insurance_company_id',r.insurance_company_id,'service_code',r.service_code,'effective_from',r.effective_from,'effective_to',r.effective_to,'actor_id',uid));
 RETURN r;
END; $function$;

CREATE OR REPLACE FUNCTION public.update_insurance_service_tariff(
 _id uuid,_base_charge numeric,_insurance_charge numeric,_top_up numeric,_effective_from date,_effective_to date DEFAULT NULL,_active boolean DEFAULT true)
RETURNS public.insurance_service_tariffs
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE r public.insurance_service_tariffs; uid uuid:=auth.uid(); old public.insurance_service_tariffs;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
 IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin') OR public.has_role(uid,'accountant')) THEN RAISE EXCEPTION 'Tariff configuration privilege required'; END IF;
 SELECT * INTO old FROM public.insurance_service_tariffs WHERE id=_id FOR UPDATE;
 IF old.id IS NULL THEN RAISE EXCEPTION 'Insurance tariff not found'; END IF;
 IF coalesce(_base_charge,0)<0 OR coalesce(_insurance_charge,0)<0 OR coalesce(_top_up,0)<0 THEN RAISE EXCEPTION 'Tariff amounts cannot be negative'; END IF;
 IF _effective_from IS NULL OR (_effective_to IS NOT NULL AND _effective_to < _effective_from) THEN RAISE EXCEPTION 'Invalid tariff effective period'; END IF;
 IF coalesce(_active,true) AND EXISTS (
   SELECT 1 FROM public.insurance_service_tariffs t
   WHERE t.id<>_id AND t.insurance_company_id=old.insurance_company_id AND t.service_code=old.service_code AND t.active
     AND t.effective_from <= coalesce(_effective_to,'9999-12-31'::date)
     AND coalesce(t.effective_to,'9999-12-31'::date) >= _effective_from
 ) THEN RAISE EXCEPTION 'An active tariff already overlaps this service and effective period'; END IF;
 UPDATE public.insurance_service_tariffs SET base_charge=coalesce(_base_charge,0),insurance_charge=coalesce(_insurance_charge,0),top_up=coalesce(_top_up,0),effective_from=_effective_from,effective_to=_effective_to,active=coalesce(_active,true),updated_at=now() WHERE id=_id RETURNING * INTO r;
 PERFORM public.record_system_audit('insurance_tariff_updated','billing','insurance_service_tariffs',r.id,'info',jsonb_build_object('insurance_company_id',r.insurance_company_id,'service_code',r.service_code,'active',r.active,'actor_id',uid));
 RETURN r;
END; $function$;

REVOKE ALL ON FUNCTION public.create_insurance_service_tariff(uuid,text,text,numeric,numeric,numeric,date,date) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.update_insurance_service_tariff(uuid,numeric,numeric,numeric,date,date,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_insurance_service_tariff(uuid,text,text,numeric,numeric,numeric,date,date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_insurance_service_tariff(uuid,numeric,numeric,numeric,date,date,boolean) TO authenticated;
COMMIT;