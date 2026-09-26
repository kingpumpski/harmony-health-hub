-- Facility context, administrator access, clinical documentation, and authenticated lab signatures.
-- Keeps database authorization authoritative while giving the UI one reusable facility context.

BEGIN;

-- 1. Replace every exposed RLS policy reference to the intentionally non-client-callable
-- is_clinical_staff(uuid) helper with the authenticated current-user wrapper.
DO $$
DECLARE
  r record;
  v_using text;
  v_check text;
BEGIN
  FOR r IN
    SELECT tablename, policyname, qual, with_check
    FROM pg_policies
    WHERE schemaname='public'
      AND (
        qual ILIKE '%is_clinical_staff(%'
        OR with_check ILIKE '%is_clinical_staff(%'
      )
      AND (
        qual NOT ILIKE '%current_user_is_clinical_staff%'
        OR with_check NOT ILIKE '%current_user_is_clinical_staff%'
      )
  LOOP
    v_using := CASE
      WHEN r.qual IS NULL THEN NULL
      ELSE replace(
        r.qual,
        'is_clinical_staff(( SELECT auth.uid() AS uid))',
        '(SELECT public.current_user_is_clinical_staff())'
      )
    END;
    v_check := CASE
      WHEN r.with_check IS NULL THEN NULL
      ELSE replace(
        r.with_check,
        'is_clinical_staff(( SELECT auth.uid() AS uid))',
        '(SELECT public.current_user_is_clinical_staff())'
      )
    END;

    IF v_using IS NOT NULL AND v_check IS NOT NULL THEN
      EXECUTE format(
        'ALTER POLICY %I ON public.%I USING (%s) WITH CHECK (%s)',
        r.policyname, r.tablename, v_using, v_check
      );
    ELSIF v_using IS NOT NULL THEN
      EXECUTE format(
        'ALTER POLICY %I ON public.%I USING (%s)',
        r.policyname, r.tablename, v_using
      );
    ELSIF v_check IS NOT NULL THEN
      EXECUTE format(
        'ALTER POLICY %I ON public.%I WITH CHECK (%s)',
        r.policyname, r.tablename, v_check
      );
    END IF;
  END LOOP;
END $$;

-- 2. Server-backed active facility context. No localStorage is used for authorization.
CREATE TABLE IF NOT EXISTS public.user_active_facilities (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  facility_id uuid NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_active_facilities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "active facility read own" ON public.user_active_facilities;
CREATE POLICY "active facility read own"
ON public.user_active_facilities FOR SELECT TO authenticated
USING (user_id=(SELECT auth.uid()) OR public.current_user_has_role('admin'::public.app_role));

DROP POLICY IF EXISTS "active facility insert own membership" ON public.user_active_facilities;
CREATE POLICY "active facility insert own membership"
ON public.user_active_facilities FOR INSERT TO authenticated
WITH CHECK (
  user_id=(SELECT auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.facility_memberships fm
    WHERE fm.user_id=(SELECT auth.uid())
      AND fm.facility_id=user_active_facilities.facility_id
      AND fm.is_active=true
  )
);

DROP POLICY IF EXISTS "active facility update own membership" ON public.user_active_facilities;
CREATE POLICY "active facility update own membership"
ON public.user_active_facilities FOR UPDATE TO authenticated
USING (user_id=(SELECT auth.uid()) OR public.current_user_has_role('admin'::public.app_role))
WITH CHECK (
  (user_id=(SELECT auth.uid()) AND EXISTS (
    SELECT 1 FROM public.facility_memberships fm
    WHERE fm.user_id=(SELECT auth.uid())
      AND fm.facility_id=user_active_facilities.facility_id
      AND fm.is_active=true
  ))
  OR public.current_user_has_role('admin'::public.app_role)
);

CREATE OR REPLACE FUNCTION public.current_user_facility_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path='public'
AS $function$
  SELECT COALESCE(
    (
      SELECT uaf.facility_id
      FROM public.user_active_facilities uaf
      JOIN public.facility_memberships fm
        ON fm.user_id=uaf.user_id
       AND fm.facility_id=uaf.facility_id
       AND fm.is_active=true
      WHERE uaf.user_id=(SELECT auth.uid())
      LIMIT 1
    ),
    (
      SELECT fm.facility_id
      FROM public.facility_memberships fm
      WHERE fm.user_id=(SELECT auth.uid())
        AND fm.is_active=true
      ORDER BY fm.created_at ASC, fm.facility_id ASC
      LIMIT 1
    )
  );
$function$;

REVOKE ALL ON FUNCTION public.current_user_facility_id() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_facility_id() TO authenticated;

CREATE OR REPLACE FUNCTION public.set_my_active_facility(_facility_id uuid)
RETURNS public.healthcare_facilities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path='public'
AS $function$
DECLARE
  v public.healthcare_facilities;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT hf.* INTO v
  FROM public.healthcare_facilities hf
  JOIN public.facility_memberships fm
    ON fm.facility_id=hf.id
   AND fm.user_id=auth.uid()
   AND fm.is_active=true
  WHERE hf.id=_facility_id AND hf.is_active=true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You are not an active member of the selected facility';
  END IF;

  INSERT INTO public.user_active_facilities(user_id,facility_id,updated_at)
  VALUES(auth.uid(),_facility_id,now())
  ON CONFLICT(user_id) DO UPDATE
    SET facility_id=excluded.facility_id, updated_at=now();

  RETURN v;
END;
$function$;

REVOKE ALL ON FUNCTION public.set_my_active_facility(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_my_active_facility(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_current_facility_context()
RETURNS TABLE(
  facility_id uuid,
  facility_name text,
  facility_code text,
  facility_type text,
  district text,
  region text,
  dhims2_uid text,
  timezone text,
  currency text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path='public'
AS $function$
  SELECT hf.id,hf.name,hf.facility_code,hf.facility_type,hf.district,hf.region,hf.dhims2_uid,
         COALESCE(fc.timezone,'Africa/Accra'),
         COALESCE(fc.currency,'GHS')
  FROM public.healthcare_facilities hf
  LEFT JOIN public.facility_configuration fc ON true
  WHERE hf.id=public.current_user_facility_id()
    AND hf.is_active=true
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.get_current_facility_context() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_current_facility_context() TO authenticated;

-- 3. Facility scope for wards/beds. Existing legacy rows remain visible to administrators;
-- new rows are automatically stamped with the caller's active facility.
ALTER TABLE public.ward_units
  ADD COLUMN IF NOT EXISTS facility_id uuid REFERENCES public.healthcare_facilities(id) ON DELETE RESTRICT;

ALTER TABLE public.ward_beds
  ADD COLUMN IF NOT EXISTS facility_id uuid REFERENCES public.healthcare_facilities(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_ward_units_facility_id ON public.ward_units(facility_id);
CREATE INDEX IF NOT EXISTS idx_ward_beds_facility_id ON public.ward_beds(facility_id);

CREATE OR REPLACE FUNCTION public.set_ward_facility_context()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path='public'
AS $function$
BEGIN
  IF NEW.facility_id IS NULL THEN
    NEW.facility_id := public.current_user_facility_id();
  END IF;
  IF NEW.facility_id IS NULL AND NOT public.current_user_has_role('admin'::public.app_role) THEN
    RAISE EXCEPTION 'Active facility context is required';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ward_units_facility_context ON public.ward_units;
CREATE TRIGGER trg_ward_units_facility_context
BEFORE INSERT ON public.ward_units
FOR EACH ROW EXECUTE FUNCTION public.set_ward_facility_context();

DROP TRIGGER IF EXISTS trg_ward_beds_facility_context ON public.ward_beds;
CREATE TRIGGER trg_ward_beds_facility_context
BEFORE INSERT ON public.ward_beds
FOR EACH ROW EXECUTE FUNCTION public.set_ward_facility_context();

DROP POLICY IF EXISTS ward_units_clinical_access ON public.ward_units;
CREATE POLICY ward_units_clinical_access ON public.ward_units
FOR SELECT TO authenticated
USING (
  public.current_user_has_role('admin'::public.app_role)
  OR facility_id IS NULL
  OR facility_id=public.current_user_facility_id()
);

DROP POLICY IF EXISTS ward_beds_clinical_access ON public.ward_beds;
CREATE POLICY ward_beds_clinical_access ON public.ward_beds
FOR SELECT TO authenticated
USING (
  public.current_user_has_role('admin'::public.app_role)
  OR facility_id IS NULL
  OR facility_id=public.current_user_facility_id()
);

-- 4. Dedicated nursing notes. Handover remains handover; this is the routine nursing
-- documentation surface for bedside observations, interventions and evaluation.
CREATE TABLE IF NOT EXISTS public.nursing_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  facility_id uuid REFERENCES public.healthcare_facilities(id) ON DELETE RESTRICT,
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  encounter_id uuid REFERENCES public.encounters(id) ON DELETE SET NULL,
  admission_id uuid REFERENCES public.admissions(id) ON DELETE SET NULL,
  author_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  note_type text NOT NULL DEFAULT 'progress',
  note_text text NOT NULL,
  assessment text,
  intervention text,
  evaluation text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_nursing_notes_facility_patient_created
  ON public.nursing_notes(facility_id,patient_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_nursing_notes_encounter
  ON public.nursing_notes(encounter_id);

ALTER TABLE public.nursing_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "nursing notes clinical access" ON public.nursing_notes;
CREATE POLICY "nursing notes clinical access" ON public.nursing_notes
FOR SELECT TO authenticated
USING (
  public.current_user_has_role('admin'::public.app_role)
  OR (
    facility_id IS NOT DISTINCT FROM public.current_user_facility_id()
    AND public.current_user_is_clinical_staff()
  )
);

DROP POLICY IF EXISTS "nursing notes clinical insert" ON public.nursing_notes;
CREATE POLICY "nursing notes clinical insert" ON public.nursing_notes
FOR INSERT TO authenticated
WITH CHECK (
  author_id=(SELECT auth.uid())
  AND (
    public.current_user_has_role('admin'::public.app_role)
    OR (
      facility_id IS NOT DISTINCT FROM public.current_user_facility_id()
      AND public.current_user_is_clinical_staff()
    )
  )
);

CREATE OR REPLACE FUNCTION public.create_nursing_note(
  _patient_id uuid,
  _note_text text,
  _note_type text DEFAULT 'progress',
  _assessment text DEFAULT NULL,
  _intervention text DEFAULT NULL,
  _evaluation text DEFAULT NULL,
  _encounter_id uuid DEFAULT NULL,
  _admission_id uuid DEFAULT NULL
)
RETURNS public.nursing_notes
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path='public'
AS $function$
DECLARE
  v public.nursing_notes;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.current_user_has_role('admin'::public.app_role)
    OR public.current_user_has_role('nurse'::public.app_role)
    OR public.current_user_has_role('specialist_nurse'::public.app_role)
    OR public.current_user_has_role('midwife'::public.app_role)
    OR public.current_user_has_role('practitioner'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Nursing documentation is not permitted for this role';
  END IF;
  IF NULLIF(pg_catalog.btrim(_note_text),'') IS NULL THEN
    RAISE EXCEPTION 'Nursing note text is required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.patients p
    WHERE p.id=_patient_id AND COALESCE(p.status,'active')<>'inactive'
  ) THEN
    RAISE EXCEPTION 'Patient not found or inactive';
  END IF;

  INSERT INTO public.nursing_notes(
    facility_id,patient_id,encounter_id,admission_id,author_id,note_type,note_text,assessment,intervention,evaluation
  )
  VALUES(
    public.current_user_facility_id(),_patient_id,_encounter_id,_admission_id,auth.uid(),
    COALESCE(NULLIF(pg_catalog.btrim(_note_type),''),'progress'),
    pg_catalog.btrim(_note_text),NULLIF(pg_catalog.btrim(_assessment),''),NULLIF(pg_catalog.btrim(_intervention),''),
    NULLIF(pg_catalog.btrim(_evaluation),'')
  )
  RETURNING * INTO v;
  RETURN v;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_nursing_note(uuid,text,text,text,text,text,uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_nursing_note(uuid,text,text,text,text,text,uuid,uuid) TO authenticated;

-- 5. Individual staff signatures. Lab technicians can save one active signature for
-- authenticated report printouts; the signature never becomes an authorization secret.
CREATE TABLE IF NOT EXISTS public.staff_signatures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  facility_id uuid REFERENCES public.healthcare_facilities(id) ON DELETE CASCADE,
  signature_data text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id,facility_id)
);

CREATE INDEX IF NOT EXISTS idx_staff_signatures_user_facility
  ON public.staff_signatures(user_id,facility_id);

ALTER TABLE public.staff_signatures ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "staff signatures read own or admin" ON public.staff_signatures;
CREATE POLICY "staff signatures read own or admin"
ON public.staff_signatures FOR SELECT TO authenticated
USING (
  user_id=(SELECT auth.uid())
  OR public.current_user_has_role('admin'::public.app_role)
);

DROP POLICY IF EXISTS "staff signatures insert own or admin" ON public.staff_signatures;
CREATE POLICY "staff signatures insert own or admin"
ON public.staff_signatures FOR INSERT TO authenticated
WITH CHECK (
  user_id=(SELECT auth.uid())
  OR public.current_user_has_role('admin'::public.app_role)
);

DROP POLICY IF EXISTS "staff signatures update own or admin" ON public.staff_signatures;
CREATE POLICY "staff signatures update own or admin"
ON public.staff_signatures FOR UPDATE TO authenticated
USING (user_id=(SELECT auth.uid()) OR public.current_user_has_role('admin'::public.app_role))
WITH CHECK (user_id=(SELECT auth.uid()) OR public.current_user_has_role('admin'::public.app_role));

CREATE OR REPLACE FUNCTION public.upsert_my_staff_signature(_signature_data text)
RETURNS public.staff_signatures
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path='public'
AS $function$
DECLARE
  v public.staff_signatures;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT (
    public.current_user_has_role('admin'::public.app_role)
    OR public.current_user_has_role('lab_technician'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'Only laboratory technicians or administrators may manage laboratory signatures';
  END IF;
  IF NULLIF(pg_catalog.btrim(_signature_data),'') IS NULL THEN
    RAISE EXCEPTION 'Signature is required';
  END IF;
  IF length(_signature_data) > 500000 THEN
    RAISE EXCEPTION 'Signature payload is too large';
  END IF;

  INSERT INTO public.staff_signatures(user_id,facility_id,signature_data,updated_at)
  VALUES(auth.uid(),public.current_user_facility_id(),_signature_data,now())
  ON CONFLICT(user_id,facility_id) DO UPDATE
    SET signature_data=excluded.signature_data,updated_at=now()
  RETURNING * INTO v;
  RETURN v;
END;
$function$;

REVOKE ALL ON FUNCTION public.upsert_my_staff_signature(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_my_staff_signature(text) TO authenticated;

COMMIT;
