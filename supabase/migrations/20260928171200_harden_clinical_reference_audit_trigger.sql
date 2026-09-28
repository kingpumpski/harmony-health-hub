CREATE OR REPLACE FUNCTION public.clinical_reference_values_audit_stamp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by = COALESCE(NEW.created_by, (select auth.uid()));
  END IF;
  NEW.review_due_at = NEW.last_reviewed_at + interval '24 months';
  NEW.updated_at = now();
  NEW.updated_by = (select auth.uid());
  RETURN NEW;
END;
$$;