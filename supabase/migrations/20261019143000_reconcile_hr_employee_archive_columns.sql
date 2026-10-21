-- Forward-only repair for installations where the HR archive migration was
-- recorded/applied incompletely and the workforce UI references archived_at.
BEGIN;

ALTER TABLE public.hr_employees
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by uuid REFERENCES auth.users(id);

CREATE OR REPLACE FUNCTION public.guard_hr_employee_archive()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.archived_at IS NULL THEN
      NEW.archived_by := NULL;
    ELSE
      IF NOT (
        (SELECT public.current_user_has_role('admin'::public.app_role))
        OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
      ) THEN
        RAISE EXCEPTION 'Only administrators can create archived employee records';
      END IF;

      IF NEW.archived_by IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'The archiving user must match the authenticated user';
      END IF;
    END IF;
  ELSIF NEW.archived_at IS DISTINCT FROM OLD.archived_at
     OR NEW.archived_by IS DISTINCT FROM OLD.archived_by THEN
    IF NOT (
      (SELECT public.current_user_has_role('admin'::public.app_role))
      OR (SELECT public.current_user_has_role('it_admin'::public.app_role))
    ) THEN
      RAISE EXCEPTION 'Only administrators can archive or restore employee records';
    END IF;

    IF NEW.archived_at IS NULL THEN
      NEW.archived_by := NULL;
    ELSIF NEW.archived_by IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'The archiving user must match the authenticated user';
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS hr_employees_record_management_guard
  ON public.hr_employees;
CREATE TRIGGER hr_employees_record_management_guard
  BEFORE INSERT OR UPDATE ON public.hr_employees
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_hr_employee_archive();

REVOKE ALL ON FUNCTION public.guard_hr_employee_archive()
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;
