-- Restrict laboratory read RPCs to authenticated callers.
-- Attachment metadata is patient-linked and must never be publicly executable.
-- Keep the existing function bodies and their facility/lineage checks intact.
DO $$
BEGIN
  IF to_regprocedure('public.get_laboratory_test_groups(boolean)') IS NULL THEN
    RAISE EXCEPTION 'Required RPC public.get_laboratory_test_groups(boolean) is missing';
  END IF;
  IF to_regprocedure('public.get_lab_result_attachments(uuid[])') IS NULL THEN
    RAISE EXCEPTION 'Required RPC public.get_lab_result_attachments(uuid[]) is missing';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.get_laboratory_test_groups(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_laboratory_test_groups(boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.get_lab_result_attachments(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_lab_result_attachments(uuid[]) TO authenticated;
