import { cn } from '@/lib/utils';
import { LucideIcon } from 'lucide-react';

interface StatCardProps {
  title: string;
  value: string | number;
  change?: string;
  changeType?: 'positive' | 'negative' | 'neutral';
  icon: LucideIcon;
  iconColor?: string;
  className?: string;
}

export default function StatCard({
  title,
  value,
  change,
  changeType = 'neutral',
  icon: Icon,
  iconColor = 'text-primary',
  className,
}: StatCardProps) {
  return (
    <div className={cn('stat-card min-h-36 rounded-2xl border-border/80 p-5 shadow-sm transition-all duration-200 hover:-translate-y-0.5 hover:shadow-md', className)}>
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">{title}</p>
          <p className="mt-2 text-3xl font-bold tracking-tight font-heading">{value}</p>
          {change && (
            <p
              className={cn(
                'mt-3 flex items-center gap-1.5 text-xs font-medium',
                changeType === 'positive' && 'text-success',
                changeType === 'negative' && 'text-critical',
                changeType === 'neutral' && 'text-muted-foreground'
              )}
            >
              <span className={cn(
                'h-1.5 w-1.5 shrink-0 rounded-full',
                changeType === 'positive' && 'bg-success',
                changeType === 'negative' && 'bg-critical',
                changeType === 'neutral' && 'bg-muted-foreground'
              )} aria-hidden="true" />
              {change}
            </p>
          )}
        </div>
        <div className={cn('shrink-0 rounded-xl bg-muted/70 p-3', iconColor)}>
          <Icon className="h-5 w-5" aria-hidden="true" />
        </div>
      </div>
    </div>
  );
}
