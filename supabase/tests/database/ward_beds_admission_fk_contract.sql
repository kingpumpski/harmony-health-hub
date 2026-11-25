BEGIN;

SELECT plan(1);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_attribute a
      ON a.attrelid = c.conrelid
     AND a.attnum = ANY(c.conkey)
    WHERE c.conrelid = 'public.ward_beds'::regclass
      AND c.confrelid = 'public.admissions'::regclass
      AND c.contype = 'f'
      AND a.attname = 'admission_id'
      AND c.confdeltype = 'r'
      AND c.convalidated
  ),
  'ward_beds.admission_id references admissions with a validated restrictive delete rule'
);

SELECT * FROM finish();
ROLLBACK;
