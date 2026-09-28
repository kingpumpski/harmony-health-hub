import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { cn } from '@/lib/utils';

interface PatientAvatarProps {
  name?: string | null;
  photoUrl?: string | null;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

function initials(name?: string | null) {
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return 'PT';
  return parts.slice(0, 2).map((part) => part[0]?.toUpperCase()).join('') || 'PT';
}

export default function PatientAvatar({ name, photoUrl, size = 'md', className }: PatientAvatarProps) {
  const sizes = { sm: 'h-7 w-7 text-[10px]', md: 'h-9 w-9 text-xs', lg: 'h-12 w-12 text-sm' } as const;
  return (
    <Avatar className={cn(sizes[size], className)} aria-label={name ? `Patient: ${name}` : 'Patient'}>
      {photoUrl ? <AvatarImage src={photoUrl} alt={name ? `Photo of ${name}` : 'Patient photo'} /> : null}
      <AvatarFallback aria-hidden="true">{initials(name)}</AvatarFallback>
    </Avatar>
  );
}
