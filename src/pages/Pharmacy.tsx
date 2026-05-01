import { useState } from 'react';
import { Pill, ClipboardList, Truck, AlertTriangle, ShieldCheck, Archive } from 'lucide-react';

const initialPrescriptions = [
  { id: 'RX-101', patient: 'Nana Baah', medication: 'Lisinopril 10mg', status: 'pending' },
  { id: 'RX-102', patient: 'Mary Owusu', medication: 'Metformin 500mg', status: 'pending' },
  { id: 'RX-103', patient: 'Kwesi Appiah', medication: 'Amoxicillin 500mg', status: 'dispensed' },
];

const initialInventory = [
  { id: 'D-001', drug: 'Paracetamol', stock: 180, reorderLevel: 50 },
  { id: 'D-002', drug: 'Amoxicillin', stock: 34, reorderLevel: 40 },
  { id: 'D-003', drug: 'Insulin', stock: 76, reorderLevel: 25 },
];

export default function Pharmacy() {
  const [prescriptions, setPrescriptions] = useState(initialPrescriptions);
  const [inventory] = useState(initialInventory);

  const handleDispense = (id: string) => {
    setPrescriptions((prev) => prev.map((prescription) => (prescription.id === id ? { ...prescription, status: 'dispensed' } : prescription)));
  };

  return (
    <div className="space-y-6 animate-fade-in">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Pharmacy Operations</h1>
          <p className="text-muted-foreground">Manage dispensing, stock and medication safety alerts.</p>
        </div>
        <button className="btn-primary inline-flex items-center gap-2">
          <Pill className="w-4 h-4" /> New Prescription
        </button>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2 card-medical p-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-semibold">Prescription Queue</h2>
              <p className="text-sm text-muted-foreground">Validate and dispense prescriptions safely.</p>
            </div>
            <ClipboardList className="w-5 h-5 text-primary" />
          </div>

          <div className="space-y-3">
            {prescriptions.map((item) => (
              <div key={item.id} className="rounded-2xl border border-border p-4 flex items-center justify-between gap-3">
                <div>
                  <p className="font-medium">{item.medication}</p>
                  <p className="text-xs text-muted-foreground">{item.patient}</p>
                </div>
                <div className="flex items-center gap-2">
                  <span className={`badge-status ${item.status === 'dispensed' ? 'badge-success' : 'badge-warning'}`}>
                    {item.status}
                  </span>
                  {item.status !== 'dispensed' && (
                    <button onClick={() => handleDispense(item.id)} className="btn-ghost text-xs">Dispense</button>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="card-medical p-6 space-y-4">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-semibold">Stock Summary</h2>
              <p className="text-sm text-muted-foreground">Current inventory levels and restock alerts.</p>
            </div>
            <Archive className="w-5 h-5 text-success" />
          </div>

          <div className="space-y-3">
            {inventory.map((item) => (
              <div key={item.id} className="rounded-2xl border border-border p-4">
                <div className="flex items-center justify-between gap-3">
                  <div>
                    <p className="font-medium">{item.drug}</p>
                    <p className="text-xs text-muted-foreground">Reorder at {item.reorderLevel} units</p>
                  </div>
                  <span className={item.stock <= item.reorderLevel ? 'text-critical font-semibold' : 'text-success font-semibold'}>
                    {item.stock} units
                  </span>
                </div>
              </div>
            ))}
          </div>

          <div className="rounded-2xl border border-border p-4 bg-warning/10">
            <div className="flex items-center gap-2 text-warning">
              <AlertTriangle className="w-4 h-4" />
              <p className="text-sm">Amoxicillin inventory below reorder level.</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
