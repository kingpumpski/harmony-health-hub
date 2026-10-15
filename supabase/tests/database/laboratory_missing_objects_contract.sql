begin;

select plan(18);

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
