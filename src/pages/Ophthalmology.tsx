import { useState } from 'react';
import { Eye, ImagePlus, Activity, Sparkles, FileUp, ShieldCheck, PlusCircle, CircleDashed } from 'lucide-react';

const aiDiagnosis = [
  'Early-stage cataract signs detected',
  'Glaucoma risk elevated due to intraocular pressure',
  'Diabetic retinopathy screening recommended',
];

export default function Ophthalmology() {
  const [exam, setExam] = useState({
    visualAcuity: '6/12',
    refraction: '+1.50 / -0.75 x 90',
    keratometry: '43.5 / 44.1 D',
    intraocularPressure: 18,
    fundusNotes: '',
    colorVision: 'Normal',
  });
  const [retinaImage, setRetinaImage] = useState<File | null>(null);
  const [aiReport, setAiReport] = useState<string[]>(aiDiagnosis);

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Ophthalmology Specialist Module</h1>
          <p className="text-muted-foreground">Eye exam workspace with AI-assisted diagnosis support.</p>
        </div>
        <button className="btn-primary inline-flex items-center gap-2">
          <Eye className="w-4 h-4" /> Register Eye Exam
        </button>
      </div>

      <div className="grid gap-6 xl:grid-cols-[minmax(320px,_360px)_1fr]">
        <div className="card-medical p-6 space-y-5">
          <div>
            <h2 className="text-lg font-semibold">Ophthalmometry Exam</h2>
            <p className="text-sm text-muted-foreground">Capture measurements for both eyes.</p>
          </div>
          <div className="grid gap-4">
            <div>
              <label className="block text-sm font-medium mb-2">Visual Acuity</label>
              <input value={exam.visualAcuity} onChange={(e) => setExam((prev) => ({ ...prev, visualAcuity: e.target.value }))} className="input-medical w-full" />
            </div>
            <div>
              <label className="block text-sm font-medium mb-2">Refraction</label>
              <input value={exam.refraction} onChange={(e) => setExam((prev) => ({ ...prev, refraction: e.target.value }))} className="input-medical w-full" />
            </div>
            <div>
              <label className="block text-sm font-medium mb-2">Keratometry</label>
              <input value={exam.keratometry} onChange={(e) => setExam((prev) => ({ ...prev, keratometry: e.target.value }))} className="input-medical w-full" />
            </div>
            <div>
              <label className="block text-sm font-medium mb-2">Intraocular Pressure (mmHg)</label>
              <input type="number" value={exam.intraocularPressure} onChange={(e) => setExam((prev) => ({ ...prev, intraocularPressure: Number(e.target.value) }))} className="input-medical w-full" />
            </div>
            <div>
              <label className="block text-sm font-medium mb-2">Color Vision</label>
              <select value={exam.colorVision} onChange={(e) => setExam((prev) => ({ ...prev, colorVision: e.target.value }))} className="input-medical w-full">
                <option>Normal</option>
                <option>Deficient</option>
                <option>Unable to complete</option>
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium mb-2">Fundoscopy Notes</label>
              <textarea value={exam.fundusNotes} onChange={(e) => setExam((prev) => ({ ...prev, fundusNotes: e.target.value }))} rows={4} className="textarea-medical w-full" />
            </div>
          </div>

          <div className="rounded-2xl border border-border p-4 bg-background/70">
            <div className="flex items-center gap-2 text-muted-foreground">
              <ImagePlus className="w-4 h-4" />
              <span>Retina Imaging</span>
            </div>
            <input type="file" accept="image/*" onChange={(e) => setRetinaImage(e.target.files?.[0] ?? null)} className="mt-3 w-full" />
            {retinaImage && <p className="mt-3 text-sm text-foreground">Selected file: {retinaImage.name}</p>}
          </div>

          <button className="btn-primary w-full py-3 inline-flex items-center justify-center gap-2">
            <FileUp className="w-4 h-4" /> Upload Exam and Analyze
          </button>
        </div>

        <div className="space-y-6">
          <div className="card-medical p-6">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h2 className="text-lg font-semibold">AI Eye Disease Detection</h2>
                <p className="text-sm text-muted-foreground">Automated screening for key ophthalmic conditions.</p>
              </div>
              <Sparkles className="w-5 h-5 text-primary" />
            </div>

            <div className="space-y-3">
              {aiReport.map((line) => (
                <div key={line} className="rounded-2xl border border-border p-4">
                  <p className="font-medium">{line}</p>
                </div>
              ))}
            </div>
          </div>

          <div className="card-medical p-6">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h2 className="text-lg font-semibold">Exam Status</h2>
                <p className="text-sm text-muted-foreground">Record outcomes and generate ophthalmology reports.</p>
              </div>
              <ShieldCheck className="w-5 h-5 text-success" />
            </div>
            <div className="space-y-4">
              <div className="rounded-2xl border border-border p-4">
                <p className="text-sm text-muted-foreground">Selected eye exam:</p>
                <p className="mt-2 font-medium">Visual acuity, Refraction, Keratometry, IOP</p>
              </div>
              <div className="rounded-2xl border border-border p-4">
                <p className="text-sm text-muted-foreground">AI findings:</p>
                <p className="mt-2 font-medium">Possible early cataract and glaucoma risk.</p>
              </div>
              <button className="btn-secondary w-full py-3 inline-flex items-center justify-center gap-2">
                <PlusCircle className="w-4 h-4" /> Add Follow-up Plan
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
