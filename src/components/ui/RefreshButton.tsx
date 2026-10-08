import { RefreshCw } from 'lucide-react';
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip';
import { cn } from '@/lib/utils';

interface RefreshButtonProps {
  onClick: () => void;
  loading?: boolean;
  label?: string;
  className?: string;
}

export default function RefreshButton({ onClick, loading = false, label = 'Refresh', className }: RefreshButtonProps) {
  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <button
          type="button"
          onClick={onClick}
          disabled={loading}
          aria-label={label}
          title={label}
          className={cn('inline-flex h-10 w-10 shrink-0 items-center justify-center rounded-full border border-border bg-muted/60 text-muted-foreground shadow-sm transition-colors hover:bg-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/30 disabled:cursor-not-allowed disabled:opacity-60', className)}
        >
          <RefreshCw className={cn('h-4 w-4', loading && 'animate-spin')} aria-hidden="true" />
        </button>
      </TooltipTrigger>
      <TooltipContent>{label}</TooltipContent>
    </Tooltip>
  );
}
