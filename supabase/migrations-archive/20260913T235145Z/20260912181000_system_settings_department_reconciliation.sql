INSERT INTO public.facility_departments(department_code,department_name) VALUES
 ('procedure','Procedures'),('imaging','Imaging / Radiology'),('ward','Ward / Inpatient'),('accounts','Accounts / Billing'),('front_desk','Front Desk')
ON CONFLICT DO NOTHING;
