BEGIN;

CREATE TABLE IF NOT EXISTS public.insurance_companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  name text NOT NULL,
  short_name text,
  phone text,
  email text,
  address text,
  contact_person text,
  active boolean NOT NULL DEFAULT true,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT insurance_companies_code_unique UNIQUE (code),
  CONSTRAINT insurance_companies_name_unique UNIQUE (name)
);

ALTER TABLE public.insurance_companies ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_insurance_companies_active_name
  ON public.insurance_companies(active, name);

CREATE OR REPLACE FUNCTION public.list_insurance_companies(_include_inactive boolean DEFAULT false)
RETURNS SETOF public.insurance_companies
LANGUAGE sql
SECURITY INVOKER
STABLE
AS $function$
  SELECT c.*
  FROM public.insurance_companies c
  WHERE (_include_inactive OR c.active)
  ORDER BY c.name;
$function$;

CREATE OR REPLACE FUNCTION public.create_insurance_company(
  _code text,
  _name text,
  _short_name text DEFAULT NULL,
  _phone text DEFAULT NULL,
  _email text DEFAULT NULL,
  _address text DEFAULT NULL,
  _contact_person text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_id uuid;
  v_code text := upper(NULLIF(pg_catalog.btrim(_code), ''));
  v_name text := NULLIF(pg_catalog.btrim(_name), '');
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    RAISE EXCEPTION 'Administrator or IT administrator role required';
  END IF;
  IF v_code IS NULL OR v_name IS NULL THEN RAISE EXCEPTION 'Insurance company code and name are required'; END IF;
  IF EXISTS (SELECT 1 FROM public.insurance_companies WHERE lower(name)=lower(v_name) OR lower(code)=lower(v_code)) THEN
    RAISE EXCEPTION 'Insurance company code or name already exists';
  END IF;

  INSERT INTO public.insurance_companies(code,name,short_name,phone,email,address,contact_person,created_by)
  VALUES(v_code,v_name,NULLIF(pg_catalog.btrim(_short_name),''),NULLIF(pg_catalog.btrim(_phone),''),
         NULLIF(pg_catalog.btrim(_email),''),NULLIF(pg_catalog.btrim(_address),''),
         NULLIF(pg_catalog.btrim(_contact_person),''),uid)
  RETURNING id INTO v_id;

  PERFORM public.record_system_audit(
    'insurance_company_created','administration','insurance_companies',v_id,'info',
    jsonb_build_object('code',v_code,'name',v_name,'actor_id',uid)
  );
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_insurance_company(
  _id uuid,
  _code text,
  _name text,
  _short_name text DEFAULT NULL,
  _phone text DEFAULT NULL,
  _email text DEFAULT NULL,
  _address text DEFAULT NULL,
  _contact_person text DEFAULT NULL,
  _active boolean DEFAULT true
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  v_code text := upper(NULLIF(pg_catalog.btrim(_code), ''));
  v_name text := NULLIF(pg_catalog.btrim(_name), '');
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (public.has_role(uid,'admin') OR public.has_role(uid,'it_admin')) THEN
    RAISE EXCEPTION 'Administrator or IT administrator role required';
  END IF;
  IF _id IS NULL OR v_code IS NULL OR v_name IS NULL THEN RAISE EXCEPTION 'Company, code and name are required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.insurance_companies WHERE id=_id) THEN RAISE EXCEPTION 'Insurance company not found'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.insurance_companies
    WHERE id<>_id AND (lower(name)=lower(v_name) OR lower(code)=lower(v_code))
  ) THEN RAISE EXCEPTION 'Insurance company code or name already exists';
  END IF;

  UPDATE public.insurance_companies
  SET code=v_code,name=v_name,short_name=NULLIF(pg_catalog.btrim(_short_name),''),
      phone=NULLIF(pg_catalog.btrim(_phone),''),email=NULLIF(pg_catalog.btrim(_email),''),
      address=NULLIF(pg_catalog.btrim(_address),''),contact_person=NULLIF(pg_catalog.btrim(_contact_person),''),
      active=COALESCE(_active,true),updated_at=now()
  WHERE id=_id;

  PERFORM public.record_system_audit(
    'insurance_company_updated','administration','insurance_companies',_id,'info',
    jsonb_build_object('code',v_code,'name',v_name,'active',COALESCE(_active,true),'actor_id',uid)
  );
  RETURN true;
END;
$function$;

INSERT INTO public.permissions(permission_key,description,is_active) VALUES ('insurance_companies','Manage the insurance company master directory',true) ON CONFLICT(permission_key) DO UPDATE SET description=EXCLUDED.description,is_active=true,updated_at=now();
INSERT INTO public.role_permissions(role,permission_key) VALUES ('it_admin','insurance_companies') ON CONFLICT DO NOTHING;

DROP POLICY IF EXISTS insurance_companies_admin_it_read ON public.insurance_companies;
CREATE POLICY insurance_companies_admin_it_read
  ON public.insurance_companies
  FOR SELECT
  TO authenticated
  USING (public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'it_admin'));

REVOKE ALL ON FUNCTION public.create_insurance_company(text,text,text,text,text,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.update_insurance_company(uuid,text,text,text,text,text,text,text,boolean) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.list_insurance_companies(boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_insurance_company(text,text,text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_insurance_company(uuid,text,text,text,text,text,text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_insurance_companies(boolean) TO authenticated;

ALTER TABLE public.patients ADD COLUMN IF NOT EXISTS insurance_company_id uuid REFERENCES public.insurance_companies(id);
ALTER TABLE public.insurance_cases ADD COLUMN IF NOT EXISTS insurance_company_id uuid REFERENCES public.insurance_companies(id);
ALTER TABLE public.insurance_claims ADD COLUMN IF NOT EXISTS insurance_company_id uuid REFERENCES public.insurance_companies(id);
ALTER TABLE public.insurance_service_tariffs ADD COLUMN IF NOT EXISTS insurance_company_id uuid REFERENCES public.insurance_companies(id);

CREATE INDEX IF NOT EXISTS idx_patients_insurance_company ON public.patients(insurance_company_id);
CREATE INDEX IF NOT EXISTS idx_insurance_cases_company ON public.insurance_cases(insurance_company_id);
CREATE INDEX IF NOT EXISTS idx_insurance_claims_company ON public.insurance_claims(insurance_company_id);
CREATE INDEX IF NOT EXISTS idx_insurance_service_tariffs_company ON public.insurance_service_tariffs(insurance_company_id);

COMMIT;