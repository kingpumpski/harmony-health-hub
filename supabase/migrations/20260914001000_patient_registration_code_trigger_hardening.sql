-- Ensure frontend patient registration can omit patient_code safely.
-- The production patients table already has generate_patient_code(), but the trigger
-- was missing, causing permanent registrations to insert NULL patient_code and the
-- frontend to reject the response because no patient identifier was returned.

CREATE OR REPLACE FUNCTION public.generate_patient_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  next_seq integer;
  ymd text;
BEGIN
  IF NEW.patient_code IS NULL OR btrim(NEW.patient_code) = '' THEN
    ymd := to_char(now(), 'YYYYMMDD');

    -- Serialize generation for the day so concurrent registrations cannot receive
    -- the same sequence number.
    PERFORM pg_advisory_xact_lock(hashtext('patient-code:' || ymd));

    SELECT COALESCE(MAX(substring(patient_code from '[0-9]{4}$')::integer), 0) + 1
      INTO next_seq
      FROM public.patients
     WHERE patient_code LIKE 'MED-' || ymd || '-%';

    NEW.patient_code := 'MED-' || ymd || '-' || lpad(next_seq::text, 4, '0');
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS patients_generate_patient_code ON public.patients;

CREATE TRIGGER patients_generate_patient_code
BEFORE INSERT ON public.patients
FOR EACH ROW
EXECUTE FUNCTION public.generate_patient_code();

REVOKE EXECUTE ON FUNCTION public.generate_patient_code() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
