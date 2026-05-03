import { cn } from '@/lib/utils';

interface MedicalLogoProps {
  size?: 'sm' | 'md' | 'lg' | 'xl';
  className?: string;
  showText?: boolean;
  variant?: 'default' | 'sidebar' | 'light';
}

export default function MedicalLogo({ 
  size = 'md', 
  className, 
  showText = true,
  variant = 'default' 
}: MedicalLogoProps) {
  const sizes = {
    sm: { icon: 'w-8 h-8', cross: 'w-4 h-4', text: 'text-lg', subtext: 'text-xs' },
    md: { icon: 'w-10 h-10', cross: 'w-5 h-5', text: 'text-xl', subtext: 'text-xs' },
    lg: { icon: 'w-14 h-14', cross: 'w-7 h-7', text: 'text-2xl', subtext: 'text-sm' },
    xl: { icon: 'w-16 h-16', cross: 'w-8 h-8', text: 'text-3xl', subtext: 'text-sm' },
  };

  const colors = {
    default: {
      bg: 'bg-primary',
      icon: 'text-primary-foreground',
      text: 'text-foreground',
      subtext: 'text-muted-foreground',
    },
    sidebar: {
      bg: 'bg-sidebar-primary',
      icon: 'text-sidebar-primary-foreground',
      text: 'text-sidebar-foreground',
      subtext: 'text-sidebar-foreground/60',
    },
    light: {
      bg: 'bg-white',
      icon: 'text-primary',
      text: 'text-white',
      subtext: 'text-white/70',
    },
  };

  const s = sizes[size];
  const c = colors[variant];

  return (
    <div className={cn('flex items-center gap-3', className)}>
      {/* Medical Cross Icon with Caduceus-inspired design */}
      <div className={cn(
        'relative rounded-xl flex items-center justify-center shadow-lg',
        s.icon,
        c.bg
      )}>
        {/* Medical Cross */}
        <svg 
          viewBox="0 0 24 24" 
          fill="none" 
          className={cn(s.cross, c.icon)}
          xmlns="http://www.w3.org/2000/svg"
        >
          {/* Cross shape */}
          <path 
            d="M9 3h6v6h6v6h-6v6H9v-6H3V9h6V3z" 
            fill="currentColor"
          />
          {/* Heart in center */}
          <path 
            d="M12 8.5c-.5-1-1.5-1.5-2.5-1.5-1.5 0-2.5 1.2-2.5 2.7 0 2.3 3 4.3 5 5.3 2-1 5-3 5-5.3 0-1.5-1-2.7-2.5-2.7-1 0-2 .5-2.5 1.5z" 
            fill="currentColor"
            opacity="0.3"
          />
        </svg>
        
        {/* Pulse line accent */}
        <div className="absolute -bottom-0.5 left-1/2 -translate-x-1/2 w-3/4 h-0.5 bg-gradient-to-r from-transparent via-white/50 to-transparent rounded-full" />
      </div>

      {showText && (
        <div>
          <h1 className={cn('font-heading font-bold leading-tight', s.text, c.text)}>
            Harmony Health
          </h1>
          <p className={cn('leading-tight', s.subtext, c.subtext)}>
            Hub
          </p>
        </div>
      )}
    </div>
  );
}
