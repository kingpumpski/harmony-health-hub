import { Building2, Settings, ShieldCheck, Users } from 'lucide-react';
import { Link } from 'react-router-dom';
import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

type SummaryCard = { key: string; value: number };

export default function SystemSuperuserDashboard() {
  const [summary, setSummary] = useState<SummaryCard[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    const load = async () => {
      const { data, error } = await supabase.rpc('get_role_dashboard_summary_for_role', {
        _requested_role: 'system_superuser',
      });
      if (!cancelled) {
        setSummary(error || !data || !Array.isArray(data.cards) ? [] : data.cards);
        setLoading(false);
      }
    };
    void load();
    return () => { cancelled = true; };
  }, []);

  const facilityCount = summary.find((card) => card.key === 'facilities')?.value ?? null;
  const staffCount = summary.find((card) => card.key === 'staff')?.value ?? null;
  const sharingCount = summary.find((card) => card.key === 'facility_sharing')?.value ?? null;

  const actions = [
    { href: '/admin/facility-onboarding', label: 'Facility Onboarding', description: 'Register and oversee facilities on the Harmony platform.', icon: Building2 },
    { href: '/admin/users', label: 'User Management', description: 'Manage platform users and operational role assignments.', icon: Users },
    { href: '/admin/settings', label: 'System Settings', description: 'Configure platform and facility operational settings.', icon: Settings },
  ];

  return (
    <div className="space-y-6">
      <section className="rounded-2xl border border-border bg-card p-6 shadow-sm">
        <div className="flex items-start gap-4">
          <div className="rounded-xl bg-primary/10 p-3"><ShieldCheck className="h-6 w-6 text-primary" /></div>
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-primary">Platform administration</p>
            <h1 className="mt-1 text-2xl font-heading font-bold">System Superuser Dashboard</h1>
            <p className="mt-1 max-w-2xl text-sm text-muted-foreground">
              Platform-level onboarding and administration. Facility staff access remains bounded by facility context.
            </p>
          </div>
        </div>
        <div className="mt-6 grid gap-3 sm:grid-cols-3">
          <div className="rounded-xl border border-border bg-muted/30 p-4">
            <p className="text-xs text-muted-foreground">Registered facilities</p>
            <p className="mt-1 text-2xl font-semibold">{loading ? '…' : facilityCount ?? 'Unavailable'}</p>
          </div>
          <div className="rounded-xl border border-border bg-muted/30 p-4">
            <p className="text-xs text-muted-foreground">Platform users</p>
            <p className="mt-1 text-2xl font-semibold">{loading ? '…' : staffCount ?? 'Unavailable'}</p>
          </div>
          <div className="rounded-xl border border-border bg-muted/30 p-4">
            <p className="text-xs text-muted-foreground">Sharing agreements</p>
            <p className="mt-1 text-2xl font-semibold">{loading ? '…' : sharingCount ?? 'Unavailable'}</p>
          </div>
        </div>
      </section>

      <section className="grid gap-4 md:grid-cols-3">
        {actions.map(({ href, label, description, icon: Icon }) => (
          <Link key={href} to={href} className="group rounded-2xl border border-border bg-card p-5 shadow-sm transition hover:border-primary/40 hover:shadow-md">
            <Icon className="h-5 w-5 text-primary" />
            <h2 className="mt-4 font-semibold group-hover:text-primary">{label}</h2>
            <p className="mt-1 text-sm text-muted-foreground">{description}</p>
          </Link>
        ))}
      </section>
    </div>
  );
}
