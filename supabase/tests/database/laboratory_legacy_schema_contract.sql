begin;

select plan(51);

select has_table(
  'public',
  'lab_test_groups',
  'laboratory test groups table must exist'
);

select has_table(
  'public',
  'lab_test_group_items',
  'laboratory test group membership table must exist'
);

select has_table(
  'public',
  'lab_result_attachments',
  'laboratory result attachment metadata table must exist'
);

select has_column('public', 'lab_result_attachments', 'id', 'attachment id must exist');
select has_column('public', 'lab_result_attachments', 'lab_order_id', 'attachment order link must exist');
select has_column('public', 'lab_result_attachments', 'lab_result_id', 'attachment result link must exist');
select has_column('public', 'lab_result_attachments', 'facility_id', 'attachment facility scope must exist');
select has_column('public', 'lab_result_attachments', 'storage_path', 'attachment storage path must exist');
select has_column('public', 'lab_result_attachments', 'file_name', 'attachment file name must exist');
select has_column('public', 'lab_result_attachments', 'mime_type', 'attachment MIME type must exist');
select has_column('public', 'lab_result_attachments', 'file_size_bytes', 'attachment file size must exist');
select has_column('public', 'lab_result_attachments', 'uploaded_by', 'attachment uploader must exist');
select has_column('public', 'lab_result_attachments', 'created_at', 'attachment creation timestamp must exist');

select has_column(
  'public',
  'lab_orders',
  'group_id',
  'lab_orders.group_id must identify its panel'
);

select has_column(
  'public',
  'lab_orders',
  'parent_order_id',
  'lab_orders.parent_order_id must identify the panel order'
);

select has_column(
  'public',
  'lab_test_catalogue',
  'sample_quantity',
  'lab_test_catalogue.sample_quantity must be available to laboratory workflows'
);

select col_type_is('public', 'lab_test_groups', 'facility_id', 'uuid', 'panel facility must be a UUID');
select col_not_null('public', 'lab_test_groups', 'facility_id', 'panel facility is required');
select col_type_is('public', 'lab_test_groups', 'group_name', 'text', 'panel name must be text');
select col_type_is('public', 'lab_test_groups', 'group_code', 'text', 'panel code must be text');
select col_type_is('public', 'lab_test_group_items', 'group_id', 'uuid', 'panel membership group must be a UUID');
select col_type_is('public', 'lab_test_group_items', 'test_id', 'uuid', 'panel membership test must be a UUID');
select col_type_is('public', 'lab_orders', 'group_id', 'uuid', 'order panel link must be a UUID');
select col_type_is('public', 'lab_orders', 'parent_order_id', 'uuid', 'parent order link must be a UUID');
select col_type_is('public', 'lab_test_catalogue', 'sample_quantity', 'text', 'sample quantity must be text');

select ok(
  to_regprocedure('public.get_laboratory_test_groups(boolean)') IS NOT NULL,
  'get_laboratory_test_groups(boolean) must be exposed'
);

select ok(
  to_regprocedure('public.get_lab_result_attachments(uuid[])') IS NOT NULL,
  'get_lab_result_attachments(uuid[]) must be exposed'
);



select has_column('public', 'lab_test_groups', 'facility_id', 'panel groups must be facility scoped');
select has_column('public', 'lab_test_groups', 'group_name', 'panel groups must expose the canonical group name');
select has_column('public', 'lab_test_groups', 'group_code', 'panel groups must expose a stable group code');
select has_column('public', 'lab_test_groups', 'default_charge', 'panel groups must expose a tariff');
select has_column('public', 'lab_test_groups', 'is_active', 'panel groups must support deactivation');
select has_column('public', 'lab_test_groups', 'created_by', 'panel groups must record their creator');

select has_column('public', 'lab_test_group_items', 'group_id', 'panel items must expose canonical group lineage');
select has_column('public', 'lab_test_group_items', 'test_id', 'panel items must expose canonical catalogue lineage');
select has_column('public', 'lab_test_group_items', 'display_order', 'panel items must preserve their order');

select ok(
  to_regprocedure('public.get_laboratory_test_groups(boolean)') IS NOT NULL
  AND pg_get_function_result(to_regprocedure('public.get_laboratory_test_groups(boolean)')) = 'jsonb',
  'get_laboratory_test_groups(boolean) must return JSONB'
);

select ok(
  to_regprocedure('public.get_lab_result_attachments(uuid[])') IS NOT NULL
  AND pg_get_function_result(to_regprocedure('public.get_lab_result_attachments(uuid[])')) = 'jsonb',
  'get_lab_result_attachments(uuid[]) must return JSONB'
);

select ok(
  to_regprocedure('public.get_lab_result_attachments(uuid[])') IS NOT NULL
  AND NOT has_function_privilege('anon', to_regprocedure('public.get_lab_result_attachments(uuid[])'), 'EXECUTE'),
  'attachment RPC must not be executable by anon'
);

select ok(
  to_regprocedure('public.get_laboratory_test_groups(boolean)') IS NOT NULL
  AND NOT has_function_privilege('anon', to_regprocedure('public.get_laboratory_test_groups(boolean)'), 'EXECUTE'),
  'laboratory panel RPC must not be executable by anon'
);

select ok(
  (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid='public.lab_test_groups'::regclass),
  'laboratory panel groups must have RLS enabled'
);

select ok(
  (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid='public.lab_test_group_items'::regclass),
  'laboratory panel items must have RLS enabled'
);

select ok(
  (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid='public.lab_result_attachments'::regclass),
  'laboratory attachments must have RLS enabled'
);

select ok(
  to_regprocedure('public.get_lab_result_attachments(uuid[])') IS NOT NULL
  AND has_function_privilege('authenticated', to_regprocedure('public.get_lab_result_attachments(uuid[])'), 'EXECUTE'),
  'authenticated users must be able to call the attachment RPC'
);

select ok(
  to_regprocedure('public.get_laboratory_test_groups(boolean)') IS NOT NULL
  AND has_function_privilege('authenticated', to_regprocedure('public.get_laboratory_test_groups(boolean)'), 'EXECUTE'),
  'authenticated users must be able to call the panel RPC'
);



select ok(
  (SELECT pg_get_constraintdef(oid) ILIKE '%ON DELETE SET NULL%'
   FROM pg_constraint
   WHERE conrelid='public.lab_result_attachments'::regclass
     AND conname='lab_result_attachments_lab_result_id_fkey'),
  'deleting a result must preserve attachment metadata by nulling its result link'
);

select ok(
  (SELECT pg_get_constraintdef(oid) NOT ILIKE '%ON DELETE CASCADE%'
   FROM pg_constraint
   WHERE conrelid='public.lab_result_attachments'::regclass
     AND conname='lab_result_attachments_facility_id_fkey'),
  'deleting a facility must not cascade-delete attachment metadata'
);

select ok(
  (SELECT pg_get_constraintdef(oid) NOT ILIKE '%ON DELETE SET NULL%'
   FROM pg_constraint
   WHERE conrelid='public.lab_result_attachments'::regclass
     AND conname='lab_result_attachments_uploaded_by_fkey'),
  'uploader deletion must not violate the required uploaded_by constraint'
);

select ok(
  (SELECT pg_get_constraintdef(oid) ILIKE '%file_size_bytes >= 1%'
          AND pg_get_constraintdef(oid) ILIKE '%file_size_bytes <= 15728640%'
   FROM pg_constraint
   WHERE conrelid='public.lab_result_attachments'::regclass
     AND conname='lab_result_attachments_file_size_bytes_check'),
  'attachment file size must be bounded to 1..15728640 bytes'
);

select * from finish();

rollback;
