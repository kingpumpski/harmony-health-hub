ALTER FUNCTION public.create_admission_workflow(uuid, text, text, text)
  SET search_path = '';

NOTIFY pgrst, 'reload schema';
