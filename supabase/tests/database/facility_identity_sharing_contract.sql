begin;

select plan(8);

select has_table('public','facility_data_sharing_agreements','facility sharing agreement table exists');
select has_table('public','facility_data_sharing_agreement_scopes','facility sharing scope table exists');
select has_function('public','current_user_facility_id');
select has_function('public','current_user_has_facility_access');
select has_function('private','current_user_has_facility_data_scope');
select has_policy('public','patients','facility_identity_select_guard');
select has_policy('public','encounters','facility_identity_select_guard');
select has_policy('public','diagnoses','facility_identity_select_guard');

select * from finish();
rollback;
