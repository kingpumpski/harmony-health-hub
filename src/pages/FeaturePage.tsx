import { ReactNode } from 'react';
import { ArrowRight, ClipboardList } from 'lucide-react';

interface FeaturePageProps {
  title: string;
  description: string;
  children?: ReactNode;
}

export default function FeaturePage({ title, description, children }: FeaturePageProps) {
  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">{title}</h1>
          <p className="text-muted-foreground">{description}</p>
        </div>
        <button className="btn-primary inline-flex items-center gap-2">
          <ArrowRight className="w-4 h-4" /> Action
        </button>
      </div>

      <div className="card-medical p-6 rounded-3xl border border-border">
        <div className="flex items-center gap-3 mb-4">
          <ClipboardList className="w-5 h-5 text-primary" />
          <p className="text-sm text-muted-foreground">This workflow is available in the HIMS and may be expanded with real clinical data services.</p>
        </div>
        {children ?? <p className="text-sm text-muted-foreground">Feature details and relevant actions will be implemented here.</p>}
      </div>
    </div>
  );
}
