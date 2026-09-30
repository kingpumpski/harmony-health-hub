BEGIN;
INSERT INTO public.report_categories(name,display_order)
SELECT 'Departmental Operations', 90
WHERE NOT EXISTS (SELECT 1 FROM public.report_categories WHERE name='Departmental Operations');

WITH cat AS (SELECT id FROM public.report_categories WHERE name='Departmental Operations' LIMIT 1)
INSERT INTO public.report_definitions(report_code,report_name,category_id,description,frequency,parameters,default_parameters,extractor_key,supported_formats,submission_deadline_day,is_active,implementation_status,audience_roles,department_code,report_scope)
SELECT v.code,v.name,cat.id,v.description,'monthly','{}'::jsonb,'{}'::jsonb,v.extractor,ARRAY['xlsx','csv'],5,true,'mapped',v.roles,NULL,'role'
FROM cat CROSS JOIN (VALUES
 ('DEP-FD-001','Front Desk Activity Summary','Daily/period activity summary for registration and appointments.','front_desk_activity',ARRAY['admin','front_desk']::text[]),
 ('DEP-ACC-001','Accounts Revenue & Billing Summary','Period billing and invoice activity for accounts operations.','accounts_activity',ARRAY['admin','accountant']::text[]),
 ('DEP-PH-001','Pharmacy Dispensing & Prescription Summary','Period prescription activity for pharmacy operations.','pharmacy_activity',ARRAY['admin','pharmacist']::text[]),
 ('DEP-LAB-001','Laboratory Work & Result Summary','Period laboratory order and result activity.','laboratory_activity',ARRAY['admin','lab_technician']::text[]),
 ('DEP-RAD-001','Radiology Activity Summary','Period imaging order activity for radiology operations.','radiology_activity',ARRAY['admin','radiologist','radiology_technician']::text[]),
 ('DEP-NUR-001','Inpatient & Nursing Operations Summary','Period admissions and inpatient activity for nursing operations.','inpatient_activity',ARRAY['admin','nurse','specialist_nurse','midwife']::text[]),
 ('DEP-CLN-001','Clinical Encounter Summary','Period encounter activity for clinicians.','clinical_activity',ARRAY['admin','practitioner','nurse','specialist_nurse','midwife']::text[]),
 ('DEP-CAN-001','Canteen Meal Service Summary','Period meal order activity for canteen operations.','canteen_activity',ARRAY['admin','canteen']::text[])
) v(code,name,description,extractor,roles)
WHERE NOT EXISTS (SELECT 1 FROM public.report_definitions r WHERE r.report_code=v.code);

INSERT INTO public.facility_report_config(facility_id,report_id,is_enabled)
SELECT f.id,r.id,true FROM public.healthcare_facilities f CROSS JOIN public.report_definitions r
WHERE r.report_code LIKE 'DEP-%'
ON CONFLICT (facility_id,report_id) DO NOTHING;
COMMIT;