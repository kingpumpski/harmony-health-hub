-- Global diagnosis / ICD catalogues are shared clinical reference data.
-- Facility ownership applies to patient/encounter clinical records, not the terminology catalogue.
drop policy if exists facility_identity_select_guard on public.facility_diagnosis_standards;
drop policy if exists facility_scope_select on public.facility_diagnosis_standards;

comment on table public.facility_diagnosis_standards is
'Optional facility-to-standard preference mapping. The underlying diagnosis standards and ICD catalogue are global shared reference data; this mapping must not restrict catalogue visibility by facility.';
