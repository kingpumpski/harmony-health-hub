CREATE OR REPLACE FUNCTION public.protect_locked_superuser()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF OLD.user_id = 'eb886ca0-5bd3-4606-a735-4c48a26a0f85'::uuid AND OLD.role = 'system_superuser' THEN
    IF TG_OP = 'DELETE' OR NEW.role <> 'system_superuser' OR NEW.user_id <> OLD.user_id THEN
      RAISE EXCEPTION 'The Super Admin role for this account is locked and cannot be removed or changed';
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS protect_locked_superuser_trg ON public.user_roles;
CREATE TRIGGER protect_locked_superuser_trg BEFORE UPDATE OR DELETE ON public.user_roles
FOR EACH ROW EXECUTE FUNCTION public.protect_locked_superuser();