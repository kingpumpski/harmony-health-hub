revoke execute on function public.validate_diagnosis_import_batch(uuid) from public, anon;
revoke execute on function public.approve_diagnosis_import_batch(uuid) from public, anon;
revoke execute on function public.import_approved_diagnosis_batch(uuid) from public, anon;
grant execute on function public.validate_diagnosis_import_batch(uuid) to authenticated;
grant execute on function public.approve_diagnosis_import_batch(uuid) to authenticated;
grant execute on function public.import_approved_diagnosis_batch(uuid) to authenticated;
