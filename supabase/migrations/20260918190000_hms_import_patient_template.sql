INSERT INTO public.hms_import_templates(code,module_code,entity_name,import_type,current_version,status)
VALUES('TMPL-PAT-PATIENT-v1','M1','patients','C',1,'active')
ON CONFLICT(code) DO UPDATE SET current_version=1,status='active',updated_at=now();
INSERT INTO public.hms_import_template_versions(template_id,version_no,schema_definition,mapping_definition,rules_definition)
SELECT id,1,
'{"required":["first_name","last_name"],"fields":["first_name","last_name","date_of_birth","gender","phone","email","address","city","ghana_card_number","blood_group","genotype","allergies","chronic_conditions","insurance_provider","insurance_number","emergency_contact_name","emergency_contact_phone"]}'::jsonb,
'{"source":"DATA","target":"patients"}'::jsonb,
'{"duplicate_policy":"quarantine","atomic_commit":true}'::jsonb
FROM public.hms_import_templates WHERE code='TMPL-PAT-PATIENT-v1'
ON CONFLICT(template_id,version_no) DO NOTHING;