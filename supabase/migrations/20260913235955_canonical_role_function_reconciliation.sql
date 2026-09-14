-- Reassert the canonical `nurse` role in the remaining operational RPCs.
-- Legacy `specialist_nurse` remains in the enum for historical compatibility,
-- but no live authorization path should depend on it.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND pg_get_functiondef(p.oid) ILIKE '%specialist_nurse%'
  LOOP
    EXECUTE replace(
      replace(pg_get_functiondef(r.oid), '''specialist_nurse''::public.app_role', '''nurse''::public.app_role'),
      '''specialist_nurse''',
      '''nurse'''
    );
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
