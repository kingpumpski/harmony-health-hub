-- Patient/facility tenancy foundation.
-- This migration establishes an explicit patient-to-facility access boundary without
-- guessing historical facility ownership. Existing ambiguous patients remain unlinked
-- until an authorized facility-linking workflow is used.
--
-- Intentionally NOT applied to production as part of this PR. The migration must be
-- validated in an isolated database/branch with cross-facility fixtures first.

CREATE TABLE IF NOT EXISTS public.patient_facility_access (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  facility_id uuid NOT NULL REFERENCES public.healthcare_facilities(id) ON DELETE RESTRICT,
  access_status text NOT NULL DEFAULT 'active'
    CHECK (access_status IN ('active','suspended','revoked')),
  access_reason text,
  linked_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  linked_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (patient_id, facility_id)
);

CREATE INDEX IF NOT EXISTS idx_patient_facility_access_patient
  ON public.patient_facility_access(patient_id, access_status);

CREATE INDEX IF NOT EXISTS idx_patient_facility_access_facility
  ON public.patient_facility_access(facility_id, access_status);

ALTER TABLE public.patient_facility_access ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "patient facility access read" ON public.patient_facility_access;
CREATE POLICY "patient facility access read"
ON public.patient_facility_access
FOR SELECT
TO authenticated
USING (
  public.has_facility_access((SELECT auth.uid()), facility_id)
  OR public.has_role((SELECT auth.uid()), 'it_admin')
);

DROP POLICY IF EXISTS "patient facility access admin write" ON public.patient_facility_access;
CREATE POLICY "patient facility access admin write"
ON public.patient_facility_access
FOR ALL
TO authenticated
USING (
  public.has_role((SELECT auth.uid()), 'admin')
  OR public.has_role((SELECT auth.uid()), 'it_admin')
)
WITH CHECK (
  public.has_role((SELECT auth.uid()), 'admin')
  OR public.has_role((SELECT auth.uid()), 'it_admin')
);

CREATE OR REPLACE FUNCTION public.hms_current_active_facility_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT uaf.facility_id
  FROM public.user_active_facilities uaf
  JOIN public.facility_memberships fm
    ON fm.user_id = uaf.user_id
   AND fm.facility_id = uaf.facility_id
   AND fm.is_active = true
  WHERE uaf.user_id = (SELECT auth.uid())
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.hms_patient_has_facility_access(_patient_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
  SELECT
    (SELECT auth.uid()) IS NOT NULL
    AND (
      public.has_role((SELECT auth.uid()), 'admin')
      OR public.has_role((SELECT auth.uid()), 'it_admin')
      OR EXISTS (
        SELECT 1
        FROM public.patient_facility_access pfa
        JOIN public.facility_memberships fm
          ON fm.facility_id = pfa.facility_id
         AND fm.user_id = (SELECT auth.uid())
         AND fm.is_active = true
        WHERE pfa.patient_id = _patient_id
          AND pfa.access_status = 'active'
      )
    );
$function$;

CREATE OR REPLACE FUNCTION public.hms_assert_patient_facility_access(_patient_id uuid)
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NOT public.hms_patient_has_facility_access(_patient_id) THEN
    RAISE EXCEPTION 'Patient facility access denied';
  END IF;
  RETURN _patient_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.link_patient_to_current_facility(
  _patient_id uuid,
  _reason text DEFAULT 'facility_registration'
)
RETURNS public.patient_facility_access
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_facility_id uuid;
  v_result public.patient_facility_access;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF NOT (
    public.has_role((SELECT auth.uid()), 'admin')
    OR public.has_role((SELECT auth.uid()), 'it_admin')
    OR public.has_role((SELECT auth.uid()), 'front_desk')
    OR public.current_user_is_clinical_staff()
  ) THEN
    RAISE EXCEPTION 'Patient facility linking is not permitted';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.patients WHERE id = _patient_id
  ) THEN
    RAISE EXCEPTION 'Patient not found';
  END IF;

  v_facility_id := public.hms_current_active_facility_id();

  IF v_facility_id IS NULL THEN
    RAISE EXCEPTION 'An active facility must be selected before linking a patient';
  END IF;

  INSERT INTO public.patient_facility_access(
    patient_id,
    facility_id,
    access_status,
    access_reason,
    linked_by,
    linked_at,
    revoked_at
  )
  VALUES (
    _patient_id,
    v_facility_id,
    'active',
    NULLIF(btrim(_reason), ''),
    (SELECT auth.uid()),
    now(),
    NULL
  )
  ON CONFLICT (patient_id, facility_id)
  DO UPDATE SET
    access_status = 'active',
    access_reason = EXCLUDED.access_reason,
    linked_by = EXCLUDED.linked_by,
    linked_at = now(),
    revoked_at = NULL
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.auto_link_patient_to_active_facility()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_facility_id uuid;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RETURN NEW;
  END IF;

  v_facility_id := public.hms_current_active_facility_id();

  IF v_facility_id IS NOT NULL THEN
    INSERT INTO public.patient_facility_access(
      patient_id,
      facility_id,
      access_status,
      access_reason,
      linked_by
    )
    VALUES (
      NEW.id,
      v_facility_id,
      'active',
      'patient_registration',
      (SELECT auth.uid())
    )
    ON CONFLICT (patient_id, facility_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_auto_link_patient_to_active_facility ON public.patients;
CREATE TRIGGER trg_auto_link_patient_to_active_facility
AFTER INSERT ON public.patients
FOR EACH ROW
EXECUTE FUNCTION public.auto_link_patient_to_active_facility();

REVOKE ALL ON TABLE public.patient_facility_access FROM anon;
REVOKE ALL ON TABLE public.patient_facility_access FROM authenticated;
GRANT SELECT ON TABLE public.patient_facility_access TO authenticated;

REVOKE ALL ON FUNCTION public.hms_current_active_facility_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hms_patient_has_facility_access(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.hms_assert_patient_facility_access(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.link_patient_to_current_facility(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.auto_link_patient_to_active_facility() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.hms_current_active_facility_id() TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_patient_has_facility_access(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.hms_assert_patient_facility_access(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.link_patient_to_current_facility(uuid, text) TO authenticated;
