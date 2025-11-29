import { AlertTriangle, X } from 'lucide-react';
import { cn } from '@/lib/utils';

interface AlertBannerProps {
  title: string;
  message: string;
  type: 'critical' | 'warning' | 'info';
  onDismiss?: () => void;
}

export default function AlertBanner({ title, message, type, onDismiss }: AlertBannerProps) {
  return (
    <div
      className={cn(
        'rounded-lg p-4 flex items-start gap-3 animate-slide-in',
        type === 'critical' && 'bg-critical/10 border border-critical/20',
        type === 'warning' && 'bg-warning/10 border border-warning/20',
        type === 'info' && 'bg-info/10 border border-info/20'
      )}
    >
      <AlertTriangle
        className={cn(
          'w-5 h-5 flex-shrink-0 mt-0.5',
          type === 'critical' && 'text-critical pulse-critical',
          type === 'warning' && 'text-warning',
          type === 'info' && 'text-info'
        )}
      />
      <div className="flex-1 min-w-0">
        <p
          className={cn(
            'font-semibold text-sm',
            type === 'critical' && 'text-critical',
            type === 'warning' && 'text-warning',
            type === 'info' && 'text-info'
          )}
        >
          {title}
        </p>
        <p className="text-sm text-foreground/80 mt-1">{message}</p>
      </div>
      {onDismiss && (
        <button
          onClick={onDismiss}
          className="p-1 rounded hover:bg-foreground/10 transition-colors"
        >
          <X className="w-4 h-4 text-muted-foreground" />
        </button>
      )}
    </div>
  );
}
