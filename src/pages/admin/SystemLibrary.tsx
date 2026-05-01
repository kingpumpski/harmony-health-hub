import { useMemo } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { BookOpen, DownloadCloud, Database, ShieldCheck, FileText, Layers } from 'lucide-react';
import { icdReferences, downloadCsvTemplate, treatmentGuidelines } from '@/lib/clinicalLibrary';

export default function SystemLibrary() {
  const { user } = useAuth();

  const isAdmin = user?.role === 'admin';

  const specialties = useMemo(
    () => [
      'Patient / Client Database',
      'Staff and Practitioners',
      'Tariff and Service Catalog',
      'Insurance Provider List',
      'Medication Inventory',
      'ICD-10 / ICD-11 Clinical References',
      'Ghana Standard Treatment Guidelines',
    ],
    [],
  );

  if (!user) return null;

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">System Administration Library</h1>
          <p className="text-muted-foreground">Admin-only system data, clinical reference material, and template downloads.</p>
        </div>
        <div className="inline-flex items-center gap-2 rounded-2xl border border-border bg-background p-3">
          <Database className="w-5 h-5 text-primary" />
          <span className="text-sm text-muted-foreground">Store ICD references, tariffs, insurance and medication catalogs centrally.</span>
        </div>
      </div>

      {!isAdmin && (
        <div className="rounded-3xl border border-warning/30 bg-warning/10 p-5 text-warning">
          Only admin users may modify system-level clinical libraries and database templates.
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
        <div className="space-y-6">
          <div className="card-medical p-6">
            <div className="flex items-center gap-3 mb-4">
              <ShieldCheck className="w-5 h-5 text-success" />
              <p className="text-sm text-muted-foreground">Use the templates below to perform bulk imports and keep records consistent.</p>
            </div>
            <div className="grid gap-3 sm:grid-cols-2">
              {(['patients', 'staff', 'tariff', 'insurance', 'medication', 'guidelines'] as const).map((template) => (
                <button
                  key={template}
                  disabled={!isAdmin}
                  onClick={() => downloadCsvTemplate(template)}
                  className="btn-secondary inline-flex items-center justify-between gap-2"
                >
                  <span>Download {template.replace(/\b\w/g, (c) => c.toUpperCase())} Template</span>
                  <DownloadCloud className="w-4 h-4" />
                </button>
              ))}
            </div>
          </div>

          <div className="card-medical p-6">
            <div className="flex items-center gap-3 mb-4">
              <BookOpen className="w-5 h-5 text-primary" />
              <p className="text-sm text-muted-foreground">ICD coding and treatment guideline snippets can be managed here.</p>
            </div>
            <div className="space-y-3">
              <div>
                <p className="text-sm font-semibold">ICD Reference Samples</p>
                <div className="mt-3 grid gap-3">
                  {icdReferences.map((item) => (
                    <div key={item.code} className="rounded-3xl border border-border p-4 bg-background/80">
                      <p className="font-medium">{item.code} • {item.description}</p>
                      <p className="text-sm text-muted-foreground">{item.category}</p>
                      <p className="text-sm mt-2">{item.guideline}</p>
                    </div>
                  ))}
                </div>
              </div>
              <div>
                <p className="text-sm font-semibold">Standard Treatment Guidelines</p>
                <div className="mt-3 space-y-3">
                  {treatmentGuidelines.map((item) => (
                    <div key={item.condition} className="rounded-3xl border border-border p-4 bg-background/80">
                      <p className="font-medium">{item.condition}</p>
                      <p className="text-sm text-muted-foreground">{item.summary}</p>
                      <p className="text-sm mt-2 font-semibold">Action:</p>
                      <p className="text-sm">{item.recommendedAction}</p>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>

        <div className="card-medical p-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <p className="text-sm font-medium">System Data Areas</p>
              <p className="text-xs text-muted-foreground">Review or update only when authorized.</p>
            </div>
            <Layers className="w-5 h-5 text-secondary" />
          </div>
          <div className="space-y-3">
            {specialties.map((item) => (
              <div key={item} className="rounded-3xl border border-border p-4">
                <p className="font-medium">{item}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
