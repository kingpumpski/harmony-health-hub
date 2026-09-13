CREATE OR REPLACE FUNCTION public.apply_temporary_membership_metadata()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.patient_code ILIKE 'TMP-%' THEN
    NEW.membership_type := 'temporary';
    IF NEW.membership_expires_at IS NULL THEN NEW.membership_expires_at := now() + interval '7 days'; END IF;
  ELSE
    NEW.membership_type := COALESCE(NEW.membership_type,'permanent');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_patient_temporary_membership ON public.patients;
CREATE TRIGGER trg_patient_temporary_membership BEFORE INSERT OR UPDATE OF patient_code ON public.patients FOR EACH ROW EXECUTE FUNCTION public.apply_temporary_membership_metadata();
REVOKE ALL ON FUNCTION public.apply_temporary_membership_metadata() FROM PUBLIC;
