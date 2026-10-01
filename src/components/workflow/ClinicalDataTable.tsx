import type { ReactNode } from 'react';
import { CheckCircle2, CircleDot, Clock3, Eye, AlertCircle } from 'lucide-react';

export type ClinicalStatus = 'completed' | 'approved' | 'started' | 'pending' | 'urgent' | 'critical' | 'cancelled' | 'in_progress' | 'ordered' | 'sample_collected' | 'released' | 'acknowledged';

const statusConfig: Record<string, { label: string; className: string; Icon: typeof CheckCircle2 }> = {
  completed: { label: 'Completed', className: 'clinical-status-success', Icon: CheckCircle2 },
  approved: { label: 'Approved', className: 'clinical-status-success', Icon: CheckCircle2 },
  acknowledged: { label: 'Acknowledged', className: 'clinical-status-success', Icon: CheckCircle2 },
  started: { label: 'Started', className: 'clinical-status-info', Icon: CircleDot },
  in_progress: { label: 'In progress', className: 'clinical-status-info', Icon: CircleDot },
  released: { label: 'Released', className: 'clinical-status-info', Icon: CircleDot },
  pending: { label: 'Pending', className: 'clinical-status-warning', Icon: Clock3 },
  ordered: { label: 'Ordered', className: 'clinical-status-warning', Icon: Clock3 },
  sample_collected: { label: 'Sample collected', className: 'clinical-status-warning', Icon: Clock3 },
  urgent: { label: 'Urgent', className: 'clinical-status-critical', Icon: AlertCircle },
  critical: { label: 'Critical', className: 'clinical-status-critical', Icon: AlertCircle },
  cancelled: { label: 'Cancelled', className: 'clinical-status-neutral', Icon: CircleDot },
};

export function ClinicalStatusBadge({ status, label }: { status?: string | null; label?: string }) {
  const key = String(status ?? 'pending').toLowerCase().replace(/\s+/g, '_');
  const config = statusConfig[key] ?? { label: label ?? String(status ?? 'Pending').replace(/_/g, ' '), className: 'clinical-status-neutral', Icon: CircleDot };
  const Icon = config.Icon;
  return (
    <span className={`clinical-status-badge ${config.className}`} aria-label={config.label}>
      <Icon className="h-3 w-3" aria-hidden="true" />
      <span>{label ?? config.label}</span>
    </span>
  );
}

export function ClinicalProgressBar({ value, label = 'Workflow progress' }: { value: number; label?: string }) {
  const safeValue = Math.min(100, Math.max(0, Number.isFinite(value) ? value : 0));
  return (
    <div className="min-w-[120px]" aria-label={`${label}: ${safeValue}%`}>
      <div className="mb-1 flex items-center justify-between text-[11px] text-muted-foreground">
        <span>{label}</span>
        <span className="font-medium text-foreground">{safeValue}%</span>
      </div>
      <div className="clinical-progress-track" role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={safeValue}>
        <span className="clinical-progress-value" style={{ width: `${safeValue}%` }} />
      </div>
    </div>
  );
}

export function ClinicalTableAction({
  label,
  onClick,
  icon = 'view',
  disabled = false,
}: {
  label: string;
  onClick: () => void;
  icon?: 'view' | 'acknowledge';
  disabled?: boolean;
}) {
  const Icon = icon === 'acknowledge' ? CheckCircle2 : Eye;
  return (
    <button type="button" onClick={onClick} disabled={disabled} className="clinical-table-action">
      <Icon className="h-3.5 w-3.5" aria-hidden="true" />
      <span>{label}</span>
    </button>
  );
}

export interface ClinicalTableFilter {
  label: string;
  value: string;
  onChange: (value: string) => void;
  options: Array<{ value: string; label: string }>;
}

interface ClinicalDataTableProps {
  title: string;
  description?: string;
  filters?: ClinicalTableFilter[];
  onSearch?: () => void;
  searchLabel?: string;
  children: ReactNode;
  loading?: boolean;
  empty?: boolean;
  emptyMessage?: string;
  meta?: ReactNode;
}

export default function ClinicalDataTable({
  title,
  description,
  filters = [],
  onSearch,
  searchLabel = 'Search',
  children,
  loading = false,
  empty = false,
  emptyMessage = 'No clinical records match the selected filters.',
  meta,
}: ClinicalDataTableProps) {
  return (
    <section className="clinical-data-table card-medical overflow-hidden" aria-labelledby="clinical-data-table-title">
      <div className="clinical-table-heading">
        <div>
          <h2 id="clinical-data-table-title" className="font-semibold">{title}</h2>
          {description && <p className="mt-0.5 text-xs text-muted-foreground">{description}</p>}
        </div>
        {meta && <div className="text-xs text-muted-foreground">{meta}</div>}
      </div>

      {filters.length > 0 && (
        <div className="clinical-table-filters" role="search" aria-label={`${title} filters`}>
          <div className="grid flex-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {filters.map((filter) => (
              <label key={filter.label} className="clinical-filter-field">
                <span>{filter.label}</span>
                <select value={filter.value} onChange={(event) => filter.onChange(event.target.value)} className="input-medical h-10">
                  {filter.options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                </select>
              </label>
            ))}
          </div>
          {onSearch && <button type="button" onClick={onSearch} className="clinical-search-button">{searchLabel}</button>}
        </div>
      )}

      {loading ? (
        <div className="space-y-2 p-4" aria-live="polite">
          <div className="h-14 animate-pulse rounded-lg bg-muted" />
          <div className="h-14 animate-pulse rounded-lg bg-muted" />
          <div className="h-14 animate-pulse rounded-lg bg-muted" />
        </div>
      ) : empty ? (
        <div className="px-5 py-14 text-center">
          <CircleDot className="mx-auto mb-2 h-8 w-8 text-muted-foreground" aria-hidden="true" />
          <p className="font-medium">{emptyMessage}</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="clinical-data-table-grid">
            {children}
          </table>
        </div>
      )}
    </section>
  );
}
