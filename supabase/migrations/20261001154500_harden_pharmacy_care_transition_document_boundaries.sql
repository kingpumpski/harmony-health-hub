-- Harden pharmacy dispensing, care-transition and patient-document facility boundaries.
BEGIN;

-- This migration is the repository representation of the live hardening applied to the same RPCs.
-- The complete function definitions are maintained in the migration history and should be replayed
-- in environments that have the corresponding schema.

ALTER FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.confirm_pharmacy_dispense(uuid)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.create_care_transition_workflow(uuid,text,text,text,boolean,boolean,date,text)
  SET search_path = pg_catalog, public;
ALTER FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text)
  SET search_path = pg_catalog, public;

REVOKE ALL ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prepare_pharmacy_dispensing(uuid,uuid,integer,text) TO authenticated;
REVOKE ALL ON FUNCTION public.confirm_pharmacy_dispense(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_pharmacy_dispense(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.create_care_transition_workflow(uuid,text,text,text,boolean,boolean,date,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_care_transition_workflow(uuid,text,text,text,boolean,boolean,date,text) TO authenticated;
REVOKE ALL ON FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upload_patient_document_metadata(uuid,text,text,text,text,bigint,text) TO authenticated;

COMMIT;
