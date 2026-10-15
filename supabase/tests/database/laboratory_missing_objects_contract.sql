begin;

select plan(8);

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

select ok(
  to_regprocedure('public.get_laboratory_test_groups(boolean)') IS NOT NULL,
  'get_laboratory_test_groups(boolean) must be exposed'
);

select ok(
  to_regprocedure('public.get_lab_result_attachments(uuid[])') IS NOT NULL,
  'get_lab_result_attachments(uuid[]) must be exposed'
);

select * from finish();

rollback;
