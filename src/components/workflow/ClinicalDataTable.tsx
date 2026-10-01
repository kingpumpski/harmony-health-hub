import { useEffect, useState, type ReactNode } from 'react';
import { CheckCircle2, CircleDot, Clock3, Eye, AlertCircle, Filter, ChevronDown, Settings2, Check } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';

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
  /** Stable workspace identifier for role-specific column preferences. */
  columnPreferenceKey?: string;
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
  columnPreferenceKey,
}: ClinicalDataTableProps) {
  const { user } = useAuth();
  const [filterOpen, setFilterOpen] = useState(false);
  const [columnMenuOpen, setColumnMenuOpen] = useState(false);
  const [tableColumns, setTableColumns] = useState<string[]>([]);
  const [hiddenColumnIndexes, setHiddenColumnIndexes] = useState<number[]>([]);
  const preferenceKey = `hms.clinical-columns:${user?.id ?? 'anonymous'}:${user?.role ?? 'unknown'}:${columnPreferenceKey ?? title}`;

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const root = document.querySelector('[data-clinical-table-key="' + CSS.escape(preferenceKey) + '"]');
    if (!root) return;
    const headers = Array.from(root.querySelectorAll<HTMLTableCellElement>('table thead tr:first-child th')).map((cell) => cell.textContent?.trim() || 'Column');
    setTableColumns(headers);
    try {
      const saved = JSON.parse(window.localStorage.getItem(preferenceKey) ?? '[]');
      setHiddenColumnIndexes(Array.isArray(saved) ? saved.filter((index) => Number.isInteger(index) && index >= 0 && index < headers.length) : []);
    } catch {
      setHiddenColumnIndexes([]);
    }
  }, [children, preferenceKey]);

  useEffect(() => {
    const root = document.querySelector('[data-clinical-table-key="' + CSS.escape(preferenceKey) + '"]');
    if (!root) return;
    root.querySelectorAll('table tr').forEach((row) => {
      Array.from(row.children).forEach((cell, index) => {
        (cell as HTMLElement).style.display = hiddenColumnIndexes.includes(index) ? 'none' : '';
      });
    });
  }, [children, hiddenColumnIndexes, preferenceKey]);

  const toggleColumn = (index: number) => {
    setHiddenColumnIndexes((current) => {
      if (current.includes(index) && current.length === tableColumns.length - 1) return current;
      const next = current.includes(index) ? current.filter((item) => item !== index) : [...current, index];
      if (typeof window !== 'undefined') window.localStorage.setItem(preferenceKey, JSON.stringify(next));
      return next;
    });
  };
  const resetColumns = () => {
    setHiddenColumnIndexes([]);
    if (typeof window !== 'undefined') window.localStorage.removeItem(preferenceKey);
  };
  return (
    <section className="clinical-data-table card-medical overflow-hidden" data-clinical-table-key={preferenceKey} aria-labelledby="clinical-data-table-title">
      <div className="clinical-table-heading">
        <div>
          <h2 id="clinical-data-table-title" className="font-semibold">{title}</h2>
          {description && <p className="mt-0.5 text-xs text-muted-foreground">{description}</p>}
        </div>
        {meta && <div className="text-xs text-muted-foreground">{meta}</div>}
      </div>
      {tableColumns.length > 0 && (
        <div className="flex justify-end border-b border-border px-4 py-2">
          <div className="relative">
            <button type="button" className="btn-secondary inline-flex items-center gap-2 text-xs" aria-expanded={columnMenuOpen} onClick={() => setColumnMenuOpen((open) => !open)}>
              <Settings2 className="h-3.5 w-3.5" /> Columns
            </button>
            {columnMenuOpen && <div className="absolute right-0 z-30 mt-1 w-64 rounded-xl border border-border bg-card p-3 shadow-xl">
              <div className="mb-2 flex items-center justify-between"><span className="text-xs font-semibold">Workspace columns</span><button type="button" className="text-xs text-primary hover:underline" onClick={resetColumns}>Reset</button></div>
              <p className="mb-2 text-[11px] text-muted-foreground">Show only information needed for this role and workflow. Preferences are saved for this workspace.</p>
              <div className="max-h-64 space-y-1 overflow-y-auto">
                {tableColumns.map((label, index) => <label key={`${index}-${label}`} className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm hover:bg-muted">
                  <input type="checkbox" checked={!hiddenColumnIndexes.includes(index)} onChange={() => toggleColumn(index)} />
                  <span className="flex-1">{label}</span>
                  {!hiddenColumnIndexes.includes(index) && <Check className="h-3.5 w-3.5 text-primary" aria-hidden="true" />}
                </label>)}
              </div>
            </div>}
          </div>
        </div>
      )}

      {(filters.length > 0 || onSearch) && (
        <div className="flex flex-wrap items-center justify-end gap-2 border-b border-border px-4 py-3 sm:px-5">
          {filters.length > 0 && <button type="button" onClick={() => setFilterOpen((open) => !open)} aria-expanded={filterOpen} className="btn-secondary inline-flex items-center gap-2">
            <Filter className="h-4 w-4" aria-hidden="true" /> Filter
            {filters.some((filter) => filter.value && !['all'].includes(filter.value)) && <span className="h-1.5 w-1.5 rounded-full bg-primary" />}
            <ChevronDown className={`h-3.5 w-3.5 transition-transform ${filterOpen ? 'rotate-180' : ''}`} aria-hidden="true" />
          </button>}
          {onSearch && <button type="button" onClick={() => { onSearch(); setFilterOpen(false); }} className="clinical-search-button">{searchLabel}</button>}
        </div>
      )}
      {filters.length > 0 && filterOpen && (
        <div className="clinical-table-filters border-b border-border bg-muted/20" role="search" aria-label={`${title} filters`}>
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
          {onSearch && <div className="flex justify-end pt-3"><button type="button" onClick={() => { onSearch(); setFilterOpen(false); }} className="clinical-search-button">Apply filters</button></div>}
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
