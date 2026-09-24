-- Database integrity boundary for bidirectional inpatient links.
-- Branch-only migration; production is intentionally unchanged.

CREATE OR REPLACE FUNCTION public.enforce_inpatient_link_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_patient_id uuid;
BEGIN
  IF TG_TABLE_NAME = 'admissions' THEN
    IF NEW.encounter_id IS NOT NULL THEN
      SELECT e.patient_id INTO v_patient_id
      FROM public.encounters e
      WHERE e.id = NEW.encounter_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Admission encounter does not exist';
      END IF;

      IF v_patient_id IS NULL OR NEW.patient_id IS NULL OR v_patient_id <> NEW.patient_id THEN
        RAISE EXCEPTION 'Admission and encounter patient linkage is inconsistent';
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'encounters' THEN
    IF NEW.admission_id IS NOT NULL THEN
      SELECT a.patient_id INTO v_patient_id
      FROM public.admissions a
      WHERE a.id = NEW.admission_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Encounter admission does not exist';
      END IF;

      IF v_patient_id IS NULL OR NEW.patient_id IS NULL OR v_patient_id <> NEW.patient_id THEN
        RAISE EXCEPTION 'Encounter and admission patient linkage is inconsistent';
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF TG_TABLE_NAME = 'ward_beds' THEN
    IF NEW.admission_id IS NOT NULL THEN
      SELECT a.patient_id INTO v_patient_id
      FROM public.admissions a
      WHERE a.id = NEW.admission_id;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Ward bed admission does not exist';
      END IF;

      IF v_patient_id IS NULL OR NEW.patient_id IS NULL OR v_patient_id <> NEW.patient_id THEN
        RAISE EXCEPTION 'Ward bed and admission patient linkage is inconsistent';
      END IF;
    END IF;

    IF NEW.status = 'occupied' AND (NEW.patient_id IS NULL OR NEW.admission_id IS NULL) THEN
      RAISE EXCEPTION 'Occupied ward bed requires patient and admission linkage';
    END IF;

    IF NEW.status <> 'occupied' AND (NEW.patient_id IS NOT NULL OR NEW.admission_id IS NOT NULL) THEN
      RAISE EXCEPTION 'Non-occupied ward bed cannot retain patient or admission linkage';
    END IF;

    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS admissions_inpatient_link_consistency_trg ON public.admissions;
CREATE TRIGGER admissions_inpatient_link_consistency_trg
BEFORE INSERT OR UPDATE OF patient_id, encounter_id
ON public.admissions
FOR EACH ROW
EXECUTE FUNCTION public.enforce_inpatient_link_consistency();

DROP TRIGGER IF EXISTS encounters_inpatient_link_consistency_trg ON public.encounters;
CREATE TRIGGER encounters_inpatient_link_consistency_trg
BEFORE INSERT OR UPDATE OF patient_id, admission_id
ON public.encounters
FOR EACH ROW
EXECUTE FUNCTION public.enforce_inpatient_link_consistency();

DROP TRIGGER IF EXISTS ward_beds_inpatient_link_consistency_trg ON public.ward_beds;
CREATE TRIGGER ward_beds_inpatient_link_consistency_trg
BEFORE INSERT OR UPDATE OF patient_id, admission_id, status
ON public.ward_beds
FOR EACH ROW
EXECUTE FUNCTION public.enforce_inpatient_link_consistency();

REVOKE ALL ON FUNCTION public.enforce_inpatient_link_consistency() FROM PUBLIC, anon, authenticated;
