-- Keep diagnosis mutation RPCs out of the anonymous/public execution surface.

REVOKE ALL ON FUNCTION public.add_encounter_diagnosis(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_encounter_diagnosis(UUID, TEXT, TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.add_encounter_diagnosis(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_encounter_diagnosis(UUID, TEXT) TO authenticated;
