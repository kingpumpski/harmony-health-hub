import type { ReactNode, ElementType } from 'react';

type Counter = { label: string; value: ReactNode; tone?: string; surface?: string };

interface OperationalWorklistShellProps {
  icon: ElementType;
  eyebrow: string;
  title: string;
  description: string;
  actions?: ReactNode;
  counters?: Counter[];
  beforeList?: ReactNode;
  listTitle: string;
  listDescription?: string;
  listMeta?: ReactNode;
  loading?: boolean;
  empty?: boolean;
  emptyIcon?: ElementType;
  emptyTitle?: string;
  emptyDescription?: string;
  children: ReactNode;
}

export default function OperationalWorklistShell({
  icon: Icon,
  eyebrow,
  title,
  description,
  actions,
  counters = [],
  beforeList,
  listTitle,
  listDescription,
  listMeta,
  loading = false,
  empty = false,
  emptyIcon: EmptyIcon = Icon,
  emptyTitle = 'No records found',
  emptyDescription = 'Records will appear here when they are available.',
  children,
}: OperationalWorklistShellProps) {
  return (
    <div className="space-y-6 animate-fade-in">
      <header className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <Icon className="h-6 w-6 shrink-0 text-primary" aria-hidden="true" />
            <span className="text-xs font-medium uppercase tracking-wide text-primary">{eyebrow}</span>
          </div>
          <h1 className="mt-1 text-2xl font-heading font-bold">{title}</h1>
          <p className="mt-1 max-w-3xl text-sm text-muted-foreground">{description}</p>
        </div>
        {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
      </header>

      {counters.length > 0 && (
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-4" aria-label={`${title} counters`}>
          {counters.map((counter) => (
            <div key={counter.label} className={`card-medical ${counter.surface ?? 'bg-card'} p-4`}>
              <p className="text-xs text-muted-foreground">{counter.label}</p>
              <p className={`mt-1 text-2xl font-bold ${counter.tone ?? 'text-foreground'}`}>{counter.value}</p>
            </div>
          ))}
        </div>
      )}

      {beforeList}

      <section className="card-medical overflow-hidden p-0" aria-labelledby={`${title.toLowerCase().replace(/\\s+/g, '-')}-worklist-heading`}>
        <div className="flex flex-col gap-2 border-b border-border px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 id={`${title.toLowerCase().replace(/\\s+/g, '-')}-worklist-heading`} className="font-semibold">{listTitle}</h2>
            {listDescription && <p className="text-xs text-muted-foreground">{listDescription}</p>}
          </div>
          {listMeta && <div className="text-xs text-muted-foreground">{listMeta}</div>}
        </div>
        {loading ? (
          <div className="space-y-2 p-4" aria-live="polite">
            <div className="h-20 animate-pulse rounded-xl bg-muted" />
            <div className="h-20 animate-pulse rounded-xl bg-muted" />
            <div className="h-20 animate-pulse rounded-xl bg-muted" />
          </div>
        ) : empty ? (
          <div className="px-5 py-14 text-center">
            <EmptyIcon className="mx-auto mb-2 h-9 w-9 text-muted-foreground" aria-hidden="true" />
            <p className="font-medium">{emptyTitle}</p>
            <p className="mt-1 text-sm text-muted-foreground">{emptyDescription}</p>
          </div>
        ) : (
          <div className="divide-y divide-border">{children}</div>
        )}
      </section>
    </div>
  );
}
