BEGIN;

SELECT plan(1);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.oid='public.ensure_updated_at()'::regprocedure
      AND COALESCE(p.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""']::text[]
  ),
  'ensure_updated_at trigger function pins an empty search_path'
);

SELECT * FROM finish();
ROLLBACK;
