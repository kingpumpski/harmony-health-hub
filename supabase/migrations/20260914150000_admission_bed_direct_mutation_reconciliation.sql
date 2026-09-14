-- Reconcile live clinical mutation authority for encounters and bed/admission surfaces.
-- Encounter creation is routed through create_encounter_workflow; direct authenticated
-- table DML is disabled. Admission/bed tables are locked down until dedicated
-- admission/bed lifecycle RPCs are introduced.

revoke insert, update, delete on table public.encounters from authenticated;
revoke insert, update, delete on table public.beds from authenticated;
revoke insert, update, delete on table public.ward_beds from authenticated;
revoke insert, update, delete on table public.admissions from authenticated;

grant execute on function public.create_encounter_workflow(uuid, text, text) to authenticated;
revoke execute on function public.create_encounter_workflow(uuid, text, text) from anon;

comment on table public.encounters is 'Clinical encounter mutations are server-authoritative through lifecycle RPCs.';
comment on table public.admissions is 'Admission mutations require an authoritative admission workflow; direct authenticated table DML is disabled pending lifecycle RPC coverage.';
comment on table public.beds is 'Bed mutations require an authoritative bed workflow; direct authenticated table DML is disabled pending lifecycle RPC coverage.';
comment on table public.ward_beds is 'Ward-bed mutations require an authoritative bed workflow; direct authenticated table DML is disabled pending lifecycle RPC coverage.';
