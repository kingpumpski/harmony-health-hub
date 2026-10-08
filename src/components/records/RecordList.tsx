import * as React from 'react';
import { Plus, MoreHorizontal } from 'lucide-react';
import RefreshButton from '@/components/ui/RefreshButton';
import { cn } from '@/lib/utils';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

export type RecordColumn<T> = {
  key: keyof T | string;
  header: string;
  width?: string;
  align?: 'left' | 'center' | 'right';
  sortable?: boolean;
  hideBelow?: 'sm' | 'md' | 'lg' | 'xl';
  render?: (row: T, index: number) => React.ReactNode;
};

export type RecordListProps<T> = {
  title: string;
  description?: string;
  data: T[];
  columns: RecordColumn<T>[];
  isLoading?: boolean;
  error?: string | Error | null;
  rowKey: (row: T, index: number) => string;
  onRowClick?: (row: T) => void;
  onAddNew?: () => void;
  onRefresh?: () => void;
  addNewLabel?: string;
  filterSlot?: React.ReactNode;
  searchSlot?: React.ReactNode;
  emptyState?: { title: string; description?: string; cta?: React.ReactNode };
  page?: number;
  pageSize?: number;
  total?: number;
  onPageChange?: (page: number) => void;
  isRefreshing?: boolean;
};

function responsiveClass(hideBelow?: RecordColumn<unknown>['hideBelow']) {
  if (!hideBelow) return '';
  return hideBelow === 'sm' ? 'hidden sm:table-cell' :
    hideBelow === 'md' ? 'hidden md:table-cell' :
    hideBelow === 'lg' ? 'hidden lg:table-cell' : 'hidden xl:table-cell';
}

export function StatusBadge({ status }: { status?: string | null }) {
  const value = String(status ?? 'unknown').replace(/_/g, ' ');
  const normalized = value.toLowerCase();
  const tone = normalized.includes('critical') || normalized.includes('cancel') || normalized.includes('rejected') || normalized.includes('failed')
    ? 'badge-critical'
    : normalized.includes('pending') || normalized.includes('waiting') || normalized.includes('urgent')
      ? 'badge-warning'
      : normalized.includes('complete') || normalized.includes('active') || normalized.includes('approved')
        ? 'badge-success'
        : 'badge-info';
  return <span className={tone}>{value}</span>;
}

function formatTimestamp(value: unknown) {
  if (!value) return '—';
  const date = new Date(String(value));
  if (Number.isNaN(date.getTime())) return String(value);
  const absolute = date.toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
  const relative = new Intl.RelativeTimeFormat(undefined, { numeric: 'auto' });
  const seconds = (date.getTime() - Date.now()) / 1000;
  const amount = Math.abs(seconds) < 60 ? Math.round(seconds) : Math.abs(seconds) < 3600 ? Math.round(seconds / 60) : Math.abs(seconds) < 86400 ? Math.round(seconds / 3600) : Math.round(seconds / 86400);
  const unit = Math.abs(seconds) < 60 ? 'second' : Math.abs(seconds) < 3600 ? 'minute' : Math.abs(seconds) < 86400 ? 'hour' : 'day';
  return { relative: relative.format(seconds < 0 ? -amount : amount, unit as Intl.RelativeTimeFormatUnit), absolute };
}

export function RecordList<T>({
  title, description, data, columns, isLoading = false, error, rowKey, onRowClick, onAddNew, onRefresh,
  addNewLabel = 'Add New Record', filterSlot, searchSlot, emptyState, page = 1, pageSize = data.length || 1,
  total = data.length, onPageChange, isRefreshing = false,
}: RecordListProps<T>) {
  const totalPages = Math.max(1, Math.ceil(total / Math.max(1, pageSize)));
  return (
    <section className="card-medical overflow-hidden" aria-labelledby={`record-list-${title.replace(/\s+/g, '-').toLowerCase()}`}>
      <header className="border-b border-border p-4 sm:p-5">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
          <div className="min-w-0">
            <h2 id={`record-list-${title.replace(/\s+/g, '-').toLowerCase()}`} className="text-lg font-semibold">{title}</h2>
            {description ? <p className="mt-1 text-sm text-muted-foreground">{description}</p> : null}
          </div>
          <div className="flex shrink-0 items-center gap-2">
            {onAddNew ? <button type="button" onClick={onAddNew} className="btn-primary h-10 px-3"><Plus className="h-4 w-4" />{addNewLabel}</button> : null}
            {onRefresh ? <RefreshButton onClick={onRefresh} loading={isRefreshing} /> : null}
          </div>
        </div>
        {(searchSlot || filterSlot) ? <div className="mt-4 flex flex-col gap-2 sm:flex-row sm:items-center">{searchSlot}{filterSlot}</div> : null}
      </header>

      {error ? <div role="alert" className="border-b border-destructive/20 bg-destructive/5 px-4 py-3 text-sm text-destructive">{error instanceof Error ? error.message : error}</div> : null}

      <div className="w-full overflow-x-auto">
        <Table className="table-medical">
          <TableHeader>
            <TableRow>
              {columns.map((column) => <TableHead key={String(column.key)} className={cn(responsiveClass(column.hideBelow), column.align === 'center' && 'text-center', column.align === 'right' && 'text-right')} style={{ width: column.width }}>{column.header}</TableHead>)}
              {onRowClick ? <TableHead className="w-12" aria-label="Actions" /> : null}
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoading ? Array.from({ length: 5 }).map((_, row) => (
              <TableRow key={row} aria-hidden="true">{columns.map((column) => <TableCell key={String(column.key)} className={responsiveClass(column.hideBelow)}><div className="h-4 animate-pulse rounded bg-muted" /></TableCell>)}</TableRow>
            )) : data.length ? data.map((row, index) => {
              const timestamp = columns.find((column) => /timestamp|updated|created|at$/i.test(column.header));
              return (
                <TableRow key={rowKey(row, index)} tabIndex={onRowClick ? 0 : undefined} role={onRowClick ? 'button' : undefined}
                  onClick={() => onRowClick?.(row)}
                  onKeyDown={(event) => { if (onRowClick && (event.key === 'Enter' || event.key === ' ')) { event.preventDefault(); onRowClick(row); } }}
                  className={cn(onRowClick && 'cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring')}
                >
                  {columns.map((column) => {
                    const raw = (row as Record<string, unknown>)[String(column.key)];
                    const rendered = column.render ? column.render(row, index) : raw == null ? '—' : String(raw);
                    const timestampValue = timestamp && String(timestamp.key) === String(column.key) ? formatTimestamp(raw) : null;
                    return <TableCell key={String(column.key)} className={cn(responsiveClass(column.hideBelow), column.align === 'center' && 'text-center', column.align === 'right' && 'text-right')}>{timestampValue && typeof timestampValue === 'object' ? <span title={timestampValue.absolute}>{timestampValue.relative}<span className="sr-only">, {timestampValue.absolute}</span></span> : rendered}</TableCell>;
                  })}
                  {onRowClick ? <TableCell className="text-right"><MoreHorizontal className="h-4 w-4 text-muted-foreground" aria-hidden="true" /></TableCell> : null}
                </TableRow>
              );
            }) : (
              <TableRow><TableCell colSpan={columns.length + (onRowClick ? 1 : 0)} className="h-32 text-center">
                <p className="font-medium">{emptyState?.title ?? 'No records found'}</p>
                {emptyState?.description ? <p className="mt-1 text-sm text-muted-foreground">{emptyState.description}</p> : null}
                {emptyState?.cta ? <div className="mt-3">{emptyState.cta}</div> : null}
              </TableCell></TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      {onPageChange && totalPages > 1 ? <footer className="flex items-center justify-between border-t border-border px-4 py-3 text-sm">
        <span className="text-muted-foreground">Page {page} of {totalPages}</span>
        <div className="flex gap-2">
          <button type="button" className="btn-secondary" disabled={page <= 1} onClick={() => onPageChange(page - 1)}>Previous</button>
          <button type="button" className="btn-secondary" disabled={page >= totalPages} onClick={() => onPageChange(page + 1)}>Next</button>
        </div>
      </footer> : null}
    </section>
  );
}
