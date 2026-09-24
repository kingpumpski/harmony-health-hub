-- Retire the legacy two-argument diagnosis RPC overload.
-- The three-argument version is the canonical workflow and validates ICD codes.
-- Keeping both overloads exposes an alternate write path with weaker validation.
DROP FUNCTION IF EXISTS public.add_encounter_diagnosis(uuid, text);
