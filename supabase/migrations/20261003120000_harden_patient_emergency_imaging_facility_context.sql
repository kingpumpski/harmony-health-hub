-- Live-applied facility-context hardening for patient, emergency and imaging workflows.
-- This migration mirrors the verified live definitions.

-- update_patient_workflow: enforce assert_patient_facility_context after row lock.
-- transition_emergency_case: enforce patient/test-mode context and case/patient facility match.
-- start_imaging_order: enforce patient/test-mode context and imaging/service-order facility match.
