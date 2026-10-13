import type { ReactNode } from 'react';
import { ArrowUpRight, type LucideIcon } from 'lucide-react';
import { Link } from 'react-router-dom';
import { cn } from '@/lib/utils';

export type DashboardKpi = {
  label: string;
  value: string | number;
  href?: string;
  description?: string;
  trend?: string;
  icon?: LucideIcon;
};

type DashboardLayoutProps = {
  headerTitle: string;
  headerSubtitle: string;
  kpiCards?: DashboardKpi[];
  secondaryKpiCards?: DashboardKpi[];
  mainContent?: ReactNode;
  sideContent?: ReactNode;
  bottomContent?: ReactNode;
};

function KpiCard({ card, secondary = false }: { card: DashboardKpi; secondary?: boolean }) {
  const Icon = card.icon;
  const content = (
    <>
      <div className="flex items-start justify-between gap-3">
        <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{card.label}</p>
        {Icon && <Icon className="h-4 w-4 shrink-0 text-primary" aria-hidden="true" />}
      </div>
      <p className={cn('mt-2 font-heading font-bold tabular-nums', secondary ? 'text-2xl' : 'text-3xl')}>{card.value}</p>
      {card.description && <p className="mt-1 text-xs text-muted-foreground">{card.description}</p>}
      {card.trend && <p className="mt-2 text-xs font-medium text-primary">{card.trend}</p>}
      {card.href && <ArrowUpRight className="absolute bottom-3 right-3 h-4 w-4 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100" aria-hidden="true" />}
    </>
  );

  const className = cn(
    'relative rounded-xl border border-border bg-white p-4 text-card-foreground shadow-sm transition-colors',
    card.href && 'group hover:border-primary/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary',
    secondary ? 'min-h-28' : 'min-h-24',
  );

  return card.href ? <Link to={card.href} className={className}>{content}</Link> : <div className={className}>{content}</div>;
}

export default function DashboardLayout({
  headerTitle,
  headerSubtitle,
  kpiCards = [],
  secondaryKpiCards = [],
  mainContent,
  sideContent,
  bottomContent,
}: DashboardLayoutProps) {
  return (
    <div className="space-y-5 animate-fade-in">
      <header>
        <h1 className="text-2xl font-heading font-bold tracking-tight">{headerTitle}</h1>
        <p className="mt-1 max-w-3xl text-sm text-muted-foreground">{headerSubtitle}</p>
      </header>

      {kpiCards.length > 0 && (
        <section aria-label="Dashboard counters" className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          {kpiCards.map((card) => <KpiCard key={card.label} card={card} />)}
        </section>
      )}

      {secondaryKpiCards.length > 0 && (
        <section aria-label="Dashboard performance metrics" className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {secondaryKpiCards.map((card) => <KpiCard key={card.label} card={card} secondary />)}
        </section>
      )}

      {(mainContent || sideContent) && (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-[minmax(0,1.85fr)_minmax(18rem,1fr)]">
          {mainContent && <div className="min-w-0">{mainContent}</div>}
          {sideContent && <aside className="min-w-0 space-y-4">{sideContent}</aside>}
        </div>
      )}

      {bottomContent && <section aria-label="Dashboard alerts">{bottomContent}</section>}
    </div>
  );
}
