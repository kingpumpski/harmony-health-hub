ALTER TABLE public.triage_assessments
  ALTER COLUMN temperature TYPE NUMERIC(5,2);
NOTIFY pgrst,'reload schema';