import { useEffect, useMemo, useState } from 'react';
import { AlertCircle, CheckCircle2, RefreshCw } from 'lucide-react';
import { applyAccessibilityPreferences, getAccessibilityPreferences, nextGenModules, type AccessibilityPreferences } from '@/lib/nextGenPlatform';
import { getNextGenFacilityContext, setNextGenFacilityContext } from '@/lib/nextGenFacilityContext';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';

type FacilityModule = { module_id: string; enabled: boolean; service_available: boolean; readiness_status: string; service_notes?: string | null };

export default function NextGenPlatformControlCenter() {
  const { user } = useAuth();
  const [preferences, setPreferences] = useState<AccessibilityPreferences>(getAccessibilityPreferences);
  const [facilityId, setFacilityId] = useState<string | null>(null);
  const [facilities, setFacilities] = useState<Array<{ id: string; name: string; facility_code?: string | null; is_active: boolean }>>([]);
  const [facilityModules, setFacilityModules] = useState<Record<string, FacilityModule>>({});
  const [loading, setLoading] = useState(true);
  const [onboarding, setOnboarding] = useState(false);
  const [facilityName, setFacilityName] = useState('');
  const [facilityCode, setFacilityCode] = useState('');
  const [facilityType, setFacilityType] = useState('hospital');
  const [error, setError] = useState<string | null>(null);
  const canConfigure = ['admin','it_admin','system_superuser'].includes(user?.role ?? '');
  const canOnboardFacility = user?.role === 'system_superuser';

  useEffect(() => applyAccessibilityPreferences(preferences), [preferences]);

  const load = async () => {
    setLoading(true); setError(null);
    try {
      const { data: authData } = await supabase.auth.getUser();
      const uid = authData.user?.id;
      if (!uid) throw new Error('Authentication is required.');
      let id: string | null = null;
      if (user?.role === 'system_superuser') {
        const { data: platformFacilities, error: facilityError } = await supabase.rpc('platform_list_facilities');
        if (facilityError) throw facilityError;
        const activeFacilities = (platformFacilities ?? []).filter((facility: any) => facility.is_active);
        setFacilities(activeFacilities);
        const storedContext = getNextGenFacilityContext();
        id = facilityId && activeFacilities.some((facility: any) => facility.id === facilityId)
          ? facilityId
          : storedContext && activeFacilities.some((facility: any) => facility.id === storedContext)
            ? storedContext
            : activeFacilities[0]?.id ?? null;
      } else {
        const { data: contexts, error: contextError } = await supabase.from('user_active_facilities').select('facility_id').eq('user_id', uid).limit(1);
        if (contextError) throw contextError;
        id = contexts?.[0]?.facility_id ?? null;
      }
      setFacilityId(id);
      if (user?.role === 'system_superuser') setNextGenFacilityContext(id);
      if (!id) { setFacilityModules({}); return; }
      const { data: rows, error: moduleError } = await supabase
        .from('hms_facility_modules')
        .select('module_id,enabled,service_available,readiness_status,service_notes')
        .eq('facility_id', id);
      if (moduleError) throw moduleError;
      setFacilityModules(Object.fromEntries((rows ?? []).map(row => [row.module_id, row as FacilityModule])));
    } catch (e) { setError(e instanceof Error ? e.message : 'Unable to load facility module configuration.'); }
    finally { setLoading(false); }
  };

  useEffect(() => { void load(); }, [user?.id]);
  useEffect(() => { if (user?.role === 'system_superuser' && facilityId) void load(); }, [facilityId]);

  const updatePreference = <K extends keyof AccessibilityPreferences>(key: K, value: AccessibilityPreferences[K]) => {
    const next = { ...preferences, [key]: value }; setPreferences(next); localStorage.setItem('harmony:accessibility:preferences', JSON.stringify(next)); applyAccessibilityPreferences(next);
  };

  const configureService = async (id: string, serviceAvailable: boolean) => {
    if (!facilityId || !canConfigure) return;
    setError(null);
    const { error: rpcError } = await supabase.rpc('set_hms_facility_module_service', {
      _facility_id: facilityId, _module_id: id, _service_available: serviceAvailable,
      _readiness_status: serviceAvailable ? 'ready' : 'not_available',
    });
    if (rpcError) setError(rpcError.message); else await load();
  };

  const toggleModule = async (id: string) => {
    if (!facilityId || !canConfigure) return;
    setError(null);
    const current = facilityModules[id];
    if (!current?.service_available) { setError('Declare that the facility provides this service before enabling its module.'); return; }
    const { error: rpcError } = await supabase.rpc('set_hms_facility_module', { _facility_id: facilityId, _module_id: id, _enabled: !current.enabled });
    if (rpcError) setError(rpcError.message); else await load();
  };

  const enabledCount = useMemo(() => Object.values(facilityModules).filter(item => item.enabled && item.service_available).length, [facilityModules]);

  return <main className="mx-auto w-full max-w-7xl space-y-8 p-4 md:p-6" aria-labelledby="platform-title">
    <header className="rounded-2xl border bg-card p-6 shadow-sm"><div className="flex flex-wrap items-start justify-between gap-4"><div><p className="text-sm font-medium text-primary">Next-generation HIMS configuration</p><h1 id="platform-title" className="mt-1 text-2xl font-semibold tracking-tight">Platform Control Center</h1><p className="mt-2 max-w-3xl text-sm text-muted-foreground">Facility configuration is server-authoritative. A service must be declared available and ready before its module can be enabled.</p></div><button type="button" onClick={() => void load()} disabled={loading} className="inline-flex items-center gap-2 rounded-lg border px-3 py-2 text-sm"><RefreshCw className="h-4 w-4" /> Refresh</button></div><div className="mt-4 flex flex-wrap gap-3 text-sm"><span className="rounded-full border px-3 py-1">{nextGenModules.length} registered modules</span><span className="rounded-full border px-3 py-1">{enabledCount} enabled at facility</span><span className="rounded-full border px-3 py-1">{facilityId ? 'Facility context active' : 'No active facility context'}</span></div></header>
    {error && <div role="alert" className="rounded-xl border border-destructive/40 bg-destructive/5 p-4 text-sm"><AlertCircle className="mr-2 inline h-4 w-4" />{error}</div>}
    {canOnboardFacility && <section className="rounded-2xl border bg-card p-6 shadow-sm" aria-labelledby="facility-onboarding-title"><div><h2 id="facility-onboarding-title" className="text-lg font-semibold">Facility onboarding</h2><p className="mt-1 text-sm text-muted-foreground">Platform Super Admins can onboard facilities independently of ordinary facility memberships. New facilities start with modules disabled until services are verified and enabled.</p></div><form className="mt-4 grid gap-3 md:grid-cols-4" onSubmit={async (event) => { event.preventDefault(); if (!facilityName.trim()) return; setOnboarding(true); setError(null); const { data: createdId, error: createError } = await supabase.rpc('platform_create_facility', { _name: facilityName.trim(), _facility_code: facilityCode.trim() || null, _facility_type: facilityType, _country_code: 'GH', _timezone: 'Africa/Accra' }); if (createError) setError(createError.message); else { setFacilityName(''); setFacilityCode(''); setFacilityType('hospital'); if (createdId) { setFacilityId(createdId); setNextGenFacilityContext(createdId); } await load(); } setOnboarding(false); }}><label className="md:col-span-2"><span className="mb-1 block text-sm font-medium">Facility name</span><input required value={facilityName} onChange={(event) => setFacilityName(event.target.value)} autoComplete="organization" className="w-full rounded-lg border bg-background px-3 py-2 text-sm" /></label><label><span className="mb-1 block text-sm font-medium">Facility code</span><input value={facilityCode} onChange={(event) => setFacilityCode(event.target.value)} autoComplete="off" className="w-full rounded-lg border bg-background px-3 py-2 text-sm" /></label><label><span className="mb-1 block text-sm font-medium">Facility type</span><select value={facilityType} onChange={(event) => setFacilityType(event.target.value)} className="w-full rounded-lg border bg-background px-3 py-2 text-sm"><option value="hospital">Hospital</option><option value="clinic">Clinic</option><option value="diagnostic_center">Diagnostic Centre</option><option value="pharmacy">Pharmacy</option><option value="laboratory">Laboratory</option><option value="other">Other</option></select></label><div className="md:col-span-4"><button type="submit" disabled={onboarding || !facilityName.trim()} className="rounded-lg border px-4 py-2 text-sm font-medium disabled:opacity-50">{onboarding ? 'Onboarding…' : 'Onboard facility'}</button></div></form></section>}
    {user?.role === 'system_superuser' && facilities.length > 0 && <section className="rounded-2xl border bg-card p-6 shadow-sm" aria-labelledby="facility-context-title"><div className="flex flex-wrap items-end justify-between gap-3"><div><h2 id="facility-context-title" className="text-lg font-semibold">Platform facility context</h2><p className="mt-1 text-sm text-muted-foreground">System Super User access is platform-wide. Select the facility whose service catalogue you want to configure.</p></div><span className="text-xs text-muted-foreground">{facilities.length} active facilities</span></div><select aria-label="Facility configuration context" className="mt-4 w-full max-w-xl rounded-lg border bg-background px-3 py-2 text-sm" value={facilityId ?? ''} onChange={(event) => { const next = event.target.value || null; setFacilityId(next); setNextGenFacilityContext(next); }}>{facilities.map((facility) => <option key={facility.id} value={facility.id}>{facility.name}{facility.facility_code ? ` · ${facility.facility_code}` : ''}</option>)}</select></section>}
    <section className="rounded-2xl border bg-card p-6 shadow-sm" aria-labelledby="accessibility-title"><h2 id="accessibility-title" className="text-lg font-semibold">Accessibility preferences</h2><div className="mt-5 grid gap-4 md:grid-cols-2 lg:grid-cols-3"><label className="flex items-center justify-between gap-4 rounded-xl border p-4"><span>Text scale</span><select aria-label="Text scale" className="rounded-md border bg-background px-2 py-1" value={preferences.textScale} onChange={(event) => updatePreference('textScale', event.target.value as AccessibilityPreferences['textScale'])}><option value="100">100%</option><option value="110">110%</option><option value="125">125%</option><option value="150">150%</option></select></label>{([['highContrast', 'High contrast'], ['reducedMotion', 'Reduced motion'], ['captions', 'Captions'], ['readAloud', 'Read aloud'], ['voiceNavigation', 'Voice navigation']] as const).map(([key, label]) => <label key={key} className="flex items-center justify-between gap-4 rounded-xl border p-4"><span>{label}</span><input type="checkbox" checked={preferences[key]} onChange={(event) => updatePreference(key, event.target.checked)} aria-label={label} /></label>)}</div></section>
    <section className="rounded-2xl border bg-card p-6 shadow-sm" aria-labelledby="modules-title"><div className="flex flex-wrap items-end justify-between gap-3"><div><h2 id="modules-title" className="text-lg font-semibold">Facility service catalogue</h2><p className="mt-1 text-sm text-muted-foreground">A module can only run when the facility actually provides the service.</p></div><span className="text-xs text-muted-foreground">{canConfigure ? 'Configuration enabled' : 'Read-only for this role'}</span></div><div className="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-3">{nextGenModules.map(module => { const state = facilityModules[module.id]; const available = state?.service_available ?? false; const enabled = state?.enabled ?? false; return <article key={module.id} className="rounded-xl border p-4"><div className="flex items-start justify-between gap-3"><div><h3 className="font-medium">{module.id}</h3><p className="text-xs text-muted-foreground">{module.domain} · {module.tier}</p></div>{enabled && available ? <CheckCircle2 className="h-5 w-5 text-primary" aria-label="Enabled" /> : <span className="rounded-full border px-2 py-1 text-[11px]">{available ? 'Service ready' : 'Service unavailable'}</span>}</div><div className="mt-3 text-xs text-muted-foreground">Readiness: {state?.readiness_status ?? 'not configured'} · {module.safetyCritical ? 'Safety-critical' : 'Operational'}</div><div className="mt-4 grid grid-cols-2 gap-2"><button type="button" disabled={!canConfigure || loading} onClick={() => void configureService(module.id, !available)} className="rounded-lg border px-3 py-2 text-xs font-medium disabled:opacity-50">{available ? 'Mark unavailable' : 'Declare service'}</button><button type="button" disabled={!canConfigure || !available || loading} aria-pressed={enabled} onClick={() => void toggleModule(module.id)} className="rounded-lg border px-3 py-2 text-xs font-medium disabled:opacity-50">{enabled ? 'Disable module' : 'Enable module'}</button></div></article>; })}</div></section>
  </main>;
}
