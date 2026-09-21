select ok(position('v_batch.created_by IS DISTINCT FROM v_user' in pg_get_functiondef(p.oid))>0,'data migration staging is creator-scoped');
select ok(position('jsonb_array_length' in pg_get_functiondef(p.oid))>0,'data migration staging bounds payload size');
select ok(position('has_facility_access(v_user,_facility_id)' in pg_get_functiondef(p.oid))>0,'facility report seeding is facility-scoped');