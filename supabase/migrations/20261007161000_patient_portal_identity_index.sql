-- Support the patient portal's case-insensitive email fallback without changing authorization.
create index if not exists idx_patients_portal_identity_email_active
  on public.patients (lower(email))
  where coalesce(status, 'active') <> 'inactive';

comment on index public.idx_patients_portal_identity_email_active
  is 'Patient portal identity lookup support for active records';
