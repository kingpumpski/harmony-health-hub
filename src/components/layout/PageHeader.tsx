import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';
import RefreshButton from '@/components/ui/RefreshButton';

type PageHeaderProps = {
  icon?: ReactNode;
  eyebrow?: string;
  title: string;
  description?: string;
  primaryAction?: ReactNode;
  onRefresh?: () => void;
  refreshing?: boolean;
  refreshLabel?: string;
  actions?: ReactNode;
  className?: string;
};

export default function PageHeader({ icon, eyebrow, title, description, primaryAction, onRefresh, refreshing, refreshLabel, actions, className }: PageHeaderProps) {
  return (
    <header className={cn('flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between', className)}>
      <div className="min-w-0">
        {(icon || eyebrow) && <div className="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-primary">{icon}{eyebrow && <span>{eyebrow}</span>}</div>}
        <h1 className="mt-1 text-2xl font-heading font-bold">{title}</h1>
        {description && <p className="mt-1 max-w-3xl text-sm text-muted-foreground">{description}</p>}
      </div>
      {(primaryAction || actions || onRefresh) && <div className="flex shrink-0 flex-wrap items-center justify-end gap-2">
        {actions}
        {primaryAction}
        {onRefresh && <RefreshButton onClick={onRefresh} loading={refreshing} label={refreshLabel} />}
      </div>}
    </header>
  );
}
