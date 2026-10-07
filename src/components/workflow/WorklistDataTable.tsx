import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { ChevronDown, ChevronLeft, ChevronRight, ChevronsUpDown, Filter, List, Settings2, X, Check } from 'lucide-react';
import RefreshButton from '@/components/ui/RefreshButton';
import { useAuth } from '@/contexts/AuthContext';

export interface WorklistColumn<T> {
  key: string;
  label: string;
  render: (row: T) => ReactNode;
  sortValue?: (row: T) => string | number | null | undefined;
  className?: string;
  /** Columns marked required cannot be hidden by user preferences. */
  required?: boolean;
  /** Optional columns can be hidden by default while remaining available in Column Settings. */
  defaultVisible?: boolean;
}

export interface WorklistFilter {
  key: string;
  label: string;
  value: string;
  onChange: (value: string) => void;
  options?: Array<{ value: string; label: string }>;
  placeholder?: string;
  type?: 'text' | 'date';
}

interface WorklistDataTableProps<T> {
  title: string;
  description?: string;
  rows: T[];
  columns: WorklistColumn<T>[];
  getRowId: (row: T) => string;
  filters?: WorklistFilter[];
  onApplyFilters?: () => void;
  onResetFilters?: () => void;
  onRefresh?: () => void;
  refreshing?: boolean;
  loading?: boolean;
  lastUpdated?: Date | null;
  pageSize?: number;
  emptyMessage?: string;
  rowActions?: (row: T) => ReactNode;
  /** Stable workspace identifier. Preferences are isolated by active user role + workspace. */
  columnPreferenceKey?: string;
}

function formatUpdatedAt(value?: Date | null) {
  if (!value) return 'Not synced yet';
  return `Last updated: ${value.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
}

export default function WorklistDataTable<T>({
  title,
  description,
  rows,
  columns,
  getRowId,
  filters = [],
  onApplyFilters,
  onResetFilters,
  onRefresh,
  refreshing = false,
  loading = false,
  lastUpdated,
  pageSize = 20,
  emptyMessage = 'No records match the current filters.',
  rowActions,
  columnPreferenceKey,
}: WorklistDataTableProps<T>) {
  const { user } = useAuth();
  const [filterOpen, setFilterOpen] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [sortKey, setSortKey] = useState<string>(columns.find((column) => column.key === 'relative' && column.sortValue)?.key ?? columns.find((column) => column.sortValue)?.key ?? '');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('desc');
  const [page, setPage] = useState(0);
  const [view, setView] = useState<'list' | 'compact'>('list');
  const [viewMenuOpen, setViewMenuOpen] = useState(false);
  const [columnMenuOpen, setColumnMenuOpen] = useState(false);
  const preferenceKey = useMemo(() => `hms.worklist.columns:${user?.id ?? 'anonymous'}:${user?.role ?? 'unknown'}:${columnPreferenceKey ?? title}`, [columnPreferenceKey, title, user?.id, user?.role]);
  const columnSignature = columns.map((column) => `${column.key}:${column.required ? 'required' : ''}:${column.defaultVisible === false ? 'optional' : 'default'}`).join('|');
  const defaultColumnKeys = () => columns.filter((column) => column.required || column.defaultVisible !== false).map((column) => column.key);
  const [visibleColumnKeys, setVisibleColumnKeys] = useState<string[]>(defaultColumnKeys);

  // The stable signature captures the only column metadata this preference loader depends on.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (typeof window === 'undefined') return;
    try {
      const saved = JSON.parse(window.localStorage.getItem(preferenceKey) ?? 'null');
      if (Array.isArray(saved)) {
        const valid = columns.filter((column) => column.required || saved.includes(column.key)).map((column) => column.key);
        setVisibleColumnKeys(valid.length ? valid : defaultColumnKeys());
      } else {
        setVisibleColumnKeys(defaultColumnKeys());
      }
    } catch {
      setVisibleColumnKeys(defaultColumnKeys());
    }
  }, [columnSignature, preferenceKey]);

  const visibleColumns = useMemo(() => columns.filter((column) => visibleColumnKeys.includes(column.key)), [columns, visibleColumnKeys]);
  const toggleColumn = (key: string) => setVisibleColumnKeys((current) => {
    if (columns.find((column) => column.key === key)?.required) return current;
    const next = current.includes(key) ? current.filter((item) => item !== key) : [...current, key];
    if (next.length === 0) return current;
    if (typeof window !== 'undefined') window.localStorage.setItem(preferenceKey, JSON.stringify(next));
    return next;
  });
  const resetColumns = () => {
    const next = defaultColumnKeys();
    setVisibleColumnKeys(next);
    if (typeof window !== 'undefined') window.localStorage.removeItem(preferenceKey);
  };

  const sortedRows = useMemo(() => {
    const column = visibleColumns.find((item) => item.key === sortKey && item.sortValue);
    if (!column?.sortValue) return rows;
    return [...rows].sort((left, right) => {
      const a = column.sortValue?.(left);
      const b = column.sortValue?.(right);
      const comparison = typeof a === 'number' && typeof b === 'number'
        ? a - b
        : String(a ?? '').localeCompare(String(b ?? ''), undefined, { numeric: true, sensitivity: 'base' });
      return sortDirection === 'asc' ? comparison : -comparison;
    });
  }, [rows, sortDirection, sortKey, visibleColumns]);

  const pageCount = Math.max(1, Math.ceil(sortedRows.length / pageSize));
  const currentPage = Math.min(page, pageCount - 1);
  const visibleRows = sortedRows.slice(currentPage * pageSize, (currentPage + 1) * pageSize);
  const visibleIds = visibleRows.map(getRowId);
  const allVisibleSelected = visibleIds.length > 0 && visibleIds.every((id) => selectedIds.has(id));

  const toggleAll = () => setSelectedIds((current) => {
    const next = new Set(current);
    if (allVisibleSelected) visibleIds.forEach((id) => next.delete(id));
    else visibleIds.forEach((id) => next.add(id));
    return next;
  });

  const toggleOne = (id: string) => setSelectedIds((current) => {
    const next = new Set(current);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    return next;
  });

  return (
    <section className="overflow-hidden rounded-2xl border border-border bg-card shadow-sm" aria-label={title}>
      <div className="flex flex-col gap-3 border-b border-border px-4 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-5">
        <div className="min-w-0">
          <h2 className="font-semibold">{title}</h2>
          {description && <p className="mt-0.5 text-xs text-muted-foreground">{description}</p>}
          <p className="mt-1 text-[11px] text-muted-foreground" aria-live="polite">{formatUpdatedAt(lastUpdated)}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative">
            <button type="button" className="btn-secondary inline-flex items-center gap-2" onClick={() => setViewMenuOpen((open) => !open)} aria-expanded={viewMenuOpen}>
              <List className="h-4 w-4" /> List View <ChevronDown className="h-3.5 w-3.5" />
            </button>
            {viewMenuOpen && <div className="absolute right-0 z-20 mt-1 min-w-36 rounded-lg border border-border bg-card p-1 shadow-lg">
              <button type="button" className="w-full rounded-md px-3 py-2 text-left text-sm hover:bg-muted" onClick={() => { setView('list'); setViewMenuOpen(false); }}>Comfortable rows</button>
              <button type="button" className="w-full rounded-md px-3 py-2 text-left text-sm hover:bg-muted" onClick={() => { setView('compact'); setViewMenuOpen(false); }}>Compact rows</button>
            </div>}
          </div>
          {filters.length > 0 && <button type="button" className={`btn-secondary inline-flex items-center gap-2 ${filterOpen ? 'border-primary text-primary' : ''}`} onClick={() => setFilterOpen((open) => !open)} aria-expanded={filterOpen}>
            <Filter className="h-4 w-4" /> Filter {filters.some((filter) => filter.value && filter.value !== 'all') && <span className="h-1.5 w-1.5 rounded-full bg-primary" />}
          </button>}
          {onRefresh && <button type="button" className="btn-secondary inline-flex items-center gap-2" onClick={onRefresh} disabled={refreshing} aria-label="Refresh worklist" title={formatUpdatedAt(lastUpdated)}>
            <RefreshCw className={`h-4 w-4 ${refreshing ? 'animate-spin' : ''}`} /> <span className="hidden md:inline">{refreshing ? 'Refreshing…' : 'Refresh'}</span>
          </button>}
          <div className="relative">
            <button type="button" className="btn-secondary inline-flex items-center gap-2" title="Configure columns" aria-label="Configure columns" aria-expanded={columnMenuOpen} onClick={() => setColumnMenuOpen((open) => !open)}>
              <Settings2 className="h-4 w-4" /> <span className="hidden lg:inline">Columns</span>
            </button>
            {columnMenuOpen && <div className="absolute right-0 z-30 mt-1 w-64 rounded-xl border border-border bg-card p-3 shadow-xl">
              <div className="mb-2 flex items-center justify-between">
                <span className="text-xs font-semibold">Workspace columns</span>
                <button type="button" className="text-xs text-primary hover:underline" onClick={resetColumns}>Reset</button>
              </div>
              <p className="mb-2 text-[11px] text-muted-foreground">Choose only the information needed for this role's workflow. Preferences are saved for this workspace.</p>
              <div className="max-h-64 space-y-1 overflow-y-auto">
                {columns.map((column) => <label key={column.key} className={`flex items-center gap-2 rounded-md px-2 py-1.5 text-sm ${column.required ? 'cursor-not-allowed opacity-75' : 'cursor-pointer hover:bg-muted'}`}>
                  <input type="checkbox" checked={visibleColumnKeys.includes(column.key)} disabled={column.required} onChange={() => toggleColumn(column.key)} aria-label={`${column.label}${column.required ? ' (required)' : ''}`} />
                  <span className="flex-1">{column.label}{column.required && <span className="ml-1 text-[10px] text-muted-foreground">Required</span>}</span>
                  {visibleColumnKeys.includes(column.key) && <Check className="h-3.5 w-3.5 text-primary" aria-hidden="true" />}
                </label>)}
              </div>
            </div>}
          </div>
          <button type="button" className="btn-secondary inline-flex items-center gap-2" title="Toggle row density" aria-label="Toggle row density" onClick={() => setView((current) => current === 'list' ? 'compact' : 'list')}>
            <Settings2 className="h-4 w-4" />
          </button>
        </div>
      </div>

      {filterOpen && <div className="border-b border-border bg-muted/20 px-4 py-4 sm:px-5">
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {filters.map((filter) => <label key={filter.key} className="block">
            <span className="mb-1 block text-xs font-medium text-muted-foreground">{filter.label}</span>
            {filter.options ? <select value={filter.value} onChange={(event) => filter.onChange(event.target.value)} className="input-medical h-10 w-full">
              {filter.options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </select> : <input type={filter.type ?? 'text'} value={filter.value} onChange={(event) => filter.onChange(event.target.value)} placeholder={filter.placeholder ?? `Filter by ${filter.label.toLowerCase()}`} className="input-medical h-10 w-full" />}
          </label>)}
        </div>
        <div className="mt-3 flex flex-wrap justify-end gap-2">
          <button type="button" className="btn-ghost inline-flex items-center gap-1.5" onClick={() => { onResetFilters?.(); setPage(0); }}><X className="h-3.5 w-3.5" /> Clear</button>
          <button type="button" className="btn-primary" onClick={() => { onApplyFilters?.(); setFilterOpen(false); setPage(0); }}>Apply filters</button>
        </div>
      </div>}

      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-2.5 sm:px-5">
        <p className="text-xs text-muted-foreground">{selectedIds.size > 0 ? `${selectedIds.size} selected · ` : ''}{sortedRows.length} record{sortedRows.length === 1 ? '' : 's'}</p>
        <label className="flex items-center gap-2 text-xs text-muted-foreground">Sort by
          <select value={sortKey} onChange={(event) => { setSortKey(event.target.value); setPage(0); }} className="input-medical h-8 max-w-44 py-1">
            {visibleColumns.filter((column) => column.sortValue).map((column) => <option key={column.key} value={column.key}>{column.label}</option>)}
          </select>
          <button type="button" className="btn-ghost p-1.5" aria-label={`Sort ${sortDirection === 'asc' ? 'descending' : 'ascending'}`} onClick={() => setSortDirection((direction) => direction === 'asc' ? 'desc' : 'asc')}><ChevronsUpDown className="h-3.5 w-3.5" /></button>
        </label>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full min-w-[760px] border-collapse text-sm">
          <thead className="bg-muted/40 text-left text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
            <tr>
              <th className="w-10 px-4 py-3"><input type="checkbox" checked={allVisibleSelected} onChange={toggleAll} aria-label="Select visible rows" /></th>
              {visibleColumns.map((column) => <th key={column.key} className={`whitespace-nowrap px-4 py-3 ${column.className ?? ''}`}>{column.label}</th>)}
              {rowActions && <th className="px-4 py-3 text-right">Actions</th>}
            </tr>
          </thead>
          <tbody>
            {loading ? <tr><td colSpan={visibleColumns.length + (rowActions ? 2 : 1)} className="px-4 py-10 text-center text-sm text-muted-foreground"><span className="inline-flex items-center gap-2"><RefreshCw className="h-4 w-4 animate-spin" /> Loading worklist…</span></td></tr> : visibleRows.map((row) => {
              const id = getRowId(row);
              return <tr key={id} className={`border-b border-[#F3F4F6] transition-colors hover:bg-muted/30 ${selectedIds.has(id) ? 'bg-primary/5' : ''} ${view === 'compact' ? 'text-xs' : ''}`}>
                <td className={`px-4 ${view === 'compact' ? 'py-2' : 'py-4'}`}><input type="checkbox" checked={selectedIds.has(id)} onChange={() => toggleOne(id)} aria-label={`Select row ${id}`} /></td>
                {visibleColumns.map((column) => <td key={column.key} className={`px-4 align-middle ${view === 'compact' ? 'py-2' : 'py-4'} ${column.className ?? ''}`}>{column.render(row)}</td>)}
                {rowActions && <td className="px-4 py-3 text-right">{rowActions(row)}</td>}
              </tr>;
            })}
          </tbody>
        </table>
        {!loading && !visibleRows.length && <div className="px-5 py-12 text-center text-sm text-muted-foreground">{emptyMessage}</div>}
      </div>

      <footer className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-4 py-3 text-xs text-muted-foreground sm:px-5">
        <span>{visibleRows.length ? `${currentPage * pageSize + 1}–${currentPage * pageSize + visibleRows.length} of ${sortedRows.length}` : `0 of ${sortedRows.length}`}</span>
        <div className="flex items-center gap-2">
          <span>Rows per page: {pageSize}</span>
          <button type="button" className="btn-ghost p-1.5" aria-label="Previous page" disabled={currentPage === 0} onClick={() => setPage((value) => Math.max(0, value - 1))}><ChevronLeft className="h-4 w-4" /></button>
          <span>Page {currentPage + 1} of {pageCount}</span>
          <button type="button" className="btn-ghost p-1.5" aria-label="Next page" disabled={currentPage >= pageCount - 1} onClick={() => setPage((value) => Math.min(pageCount - 1, value + 1))}><ChevronRight className="h-4 w-4" /></button>
        </div>
      </footer>
    </section>
  );
}
