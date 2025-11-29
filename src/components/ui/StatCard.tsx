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
    <div className={cn('stat-card', className)}>
      <div className="flex items-start justify-between">
        <div>
          <p className="text-sm text-muted-foreground font-medium">{title}</p>
          <p className="text-3xl font-bold mt-2 font-heading">{value}</p>
          {change && (
            <p
              className={cn(
                'text-xs mt-2 font-medium',
                changeType === 'positive' && 'text-success',
                changeType === 'negative' && 'text-critical',
                changeType === 'neutral' && 'text-muted-foreground'
              )}
            >
              {change}
            </p>
          )}
        </div>
        <div className={cn('p-3 rounded-xl bg-muted', iconColor)}>
          <Icon className="w-6 h-6" />
        </div>
      </div>
    </div>
  );
}
