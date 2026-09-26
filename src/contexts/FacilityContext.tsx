import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { supabase } from '@/integrations/supabase/client';

export interface FacilityContextRecord {
  facility_id: string;
  facility_name: string;
  facility_code: string | null;
  facility_type: string;
  district: string | null;
  region: string | null;
  dhims2_uid: string | null;
  timezone: string;
  currency: string;
}

interface FacilityContextValue {
  facility: FacilityContextRecord | null;
  facilities: FacilityContextRecord[];
  loading: boolean;
  error: string | null;
  switchFacility: (facilityId: string) => Promise<void>;
  refreshFacility: () => Promise<void>;
}

const Context = createContext<FacilityContextValue | undefined>(undefined);

export function FacilityProvider({ children }: { children: ReactNode }) {
  const [facility, setFacility] = useState<FacilityContextRecord | null>(null);
  const [facilities, setFacilities] = useState<FacilityContextRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refreshFacility = async () => {
    setLoading(true);
    setError(null);
    try {
      const [{ data: current, error: currentError }, { data: available, error: availableError }] = await Promise.all([
        supabase.rpc('get_current_facility_context'),
        supabase.from('healthcare_facilities').select('id,name,facility_code,facility_type,district,region,dhims2_uid,is_active').eq('is_active', true).order('name'),
      ]);
      if (currentError) throw new Error(currentError.message);
      if (availableError) throw new Error(availableError.message);
      const rows = (available ?? []).map((row: any) => ({
        facility_id: row.id,
        facility_name: row.name,
        facility_code: row.facility_code ?? null,
        facility_type: row.facility_type,
        district: row.district ?? null,
        region: row.region ?? null,
        dhims2_uid: row.dhims2_uid ?? null,
        timezone: current?.[0]?.timezone ?? 'Africa/Accra',
        currency: current?.[0]?.currency ?? 'GHS',
      })) as FacilityContextRecord[];
      setFacilities(rows);
      setFacility((current?.[0] as FacilityContextRecord | undefined) ?? rows[0] ?? null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unable to load facility context.');
      setFacility(null);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void refreshFacility();
  }, []);

  const switchFacility = async (facilityId: string) => {
    const { data, error: switchError } = await supabase.rpc('set_my_active_facility', { _facility_id: facilityId });
    if (switchError) throw new Error(switchError.message);
    const row = data as any;
    setFacility({
      facility_id: row.id,
      facility_name: row.name,
      facility_code: row.facility_code ?? null,
      facility_type: row.facility_type,
      district: row.district ?? null,
      region: row.region ?? null,
      dhims2_uid: row.dhims2_uid ?? null,
      timezone: facility?.timezone ?? 'Africa/Accra',
      currency: facility?.currency ?? 'GHS',
    });
  };

  const value = useMemo(() => ({ facility, facilities, loading, error, switchFacility, refreshFacility }), [facility, facilities, loading, error]);
  return <Context.Provider value={value}>{children}</Context.Provider>;
}

export function useFacilityContext() {
  const context = useContext(Context);
  if (!context) throw new Error('useFacilityContext must be used within FacilityProvider');
  return context;
}
