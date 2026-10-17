-- Master HIMS reconciliation: enforce a consistent server-side audit trail for
-- operational transitions and prevent accidental direct writes through the
-- authenticated PostgREST role. Existing secure RPCs remain the write path.

-- Laboratory compatibility grants are no longer required after UI reconciliation.
REVOKE INSERT, UPDATE, DELETE ON public.lab_orders FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.lab_results FROM authenticated;

-- Keep operational HIMS tables server-transitioned. These statements are
-- idempotent and intentionally do not alter SELECT policies.
REVOKE INSERT, UPDATE, DELETE ON public.emergency_cases FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.theatre_cases FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.transfusion_records FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.insurance_claims FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.nursing_care_plans FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.nursing_shift_handovers FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.ward_units FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.ward_beds FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.medication_administrations FROM authenticated;

-- Direct prescription mutation must also remain behind the clinical workflow.
REVOKE INSERT, UPDATE, DELETE ON public.prescriptions FROM authenticated;

-- Explicitly preserve read access for authenticated clinical users; RLS still
-- controls which rows they can see.
GRANT SELECT ON public.lab_orders, public.lab_results TO authenticated;
GRANT SELECT ON public.emergency_cases, public.theatre_cases, public.transfusion_records,
  public.insurance_claims, public.nursing_care_plans, public.nursing_shift_handovers,
  public.ward_units, public.ward_beds, public.medication_administrations, public.prescriptions
  TO authenticated;
