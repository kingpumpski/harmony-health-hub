-- The four-argument compatibility wrapper delegates facility resolution to the
-- canonical five-argument implementation. Pin its search path to an empty path too.
ALTER FUNCTION public.create_ward_unit(TEXT, TEXT, TEXT, TEXT)
  SET search_path = '';

NOTIFY pgrst, 'reload schema';
