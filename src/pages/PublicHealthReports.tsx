import { useMemo, useState } from 'react';
import { FileText, CalendarDays, Globe2, BarChart3, ShieldCheck } from 'lucide-react';

const reportTemplates = [
  { id: 'outpatient', title: 'Statement of Outpatient', frequency: 'Monthly' },
  { id: 'midwife', title: 'Midwife Form A', frequency: 'Monthly' },
  { id: 'vaccination', title: 'Vaccination Report', frequency: 'Monthly' },
  { id: 'hiv', title: 'HIV Report', frequency: 'Monthly' },
  { id: 'malaria', title: 'Malaria Report', frequency: 'Monthly' },
  { id: 'idsr-weekly', title: 'Weekly IDSR', frequency: 'Weekly' },
  { id: 'idsr-monthly', title: 'Monthly IDSR', frequency: 'Monthly' },
];

export default function PublicHealthReports() {
  const [generated, setGenerated] = useState<string[]>(['OPD morbidity report', 'Weekly IDSR']);

  const nextRun = useMemo(() => {
    const next = new Date();
    next.setDate(5);
    return next.toLocaleDateString();
  }, []);

  const handleGenerate = (template: string) => {
    setGenerated((prev) => [template, ...prev].slice(0, 5));
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Public Health Reporting</h1>
          <p className="text-muted-foreground">Generate regulatory reports for Ghana Health Service and national programs.</p>
        </div>
        <button className="btn-primary inline-flex items-center gap-2">
          <Globe2 className="w-4 h-4" /> Generate Monthly Reports
        </button>
      </div>

      <div className="grid gap-6 lg:grid-cols-[2fr_1fr]">
        <div className="card-medical p-6">
          <div className="flex items-center justify-between mb-5">
            <div>
              <h2 className="text-lg font-semibold">Report Templates</h2>
              <p className="text-sm text-muted-foreground">Generate forms required by public health authorities.</p>
            </div>
            <CalendarDays className="w-5 h-5 text-primary" />
          </div>

          <div className="grid gap-4">
            {reportTemplates.map((template) => (
              <div key={template.id} className="rounded-2xl border border-border p-4 flex items-center justify-between gap-3">
                <div>
                  <p className="font-medium">{template.title}</p>
                  <p className="text-xs text-muted-foreground">{template.frequency}</p>
                </div>
                <button onClick={() => handleGenerate(template.title)} className="btn-secondary text-xs">Generate</button>
              </div>
            ))}
          </div>
        </div>

        <div className="card-medical p-6">
          <div className="flex items-center gap-3 mb-4">
            <FileText className="w-5 h-5 text-success" />
            <div>
              <h2 className="text-lg font-semibold">Next Automatic Run</h2>
              <p className="text-sm text-muted-foreground">Reports scheduled to run automatically on the 5th of every month.</p>
            </div>
          </div>
          <div className="rounded-3xl border border-border p-6 bg-background/60">
            <p className="text-sm text-muted-foreground">Next automated generation date</p>
            <p className="mt-3 text-2xl font-semibold">{nextRun}</p>
          </div>
        </div>
      </div>

      <div className="card-medical p-6">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="text-lg font-semibold">Recent Generated Reports</h2>
            <p className="text-sm text-muted-foreground">Latest outputs available for submission and health monitoring.</p>
          </div>
          <ShieldCheck className="w-5 h-5 text-success" />
        </div>
        <div className="grid gap-3">
          {generated.map((report) => (
            <div key={report} className="rounded-2xl border border-border p-4 flex items-center gap-3">
              <BarChart3 className="w-5 h-5 text-primary" />
              <span className="font-medium">{report}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
