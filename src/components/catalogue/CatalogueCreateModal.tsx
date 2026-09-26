import { useState } from 'react';
import { Plus, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';

type CreateKind = 'service' | 'pharmacy' | 'lab';

interface Props {
  kind: CreateKind;
  initialName: string;
  userRoles: string[];
  userPermissions: string[];
  userDepartment?: string;
  onCreated: (created: any) => void;
  onClose: () => void;
}

export default function CatalogueCreateModal({ kind, initialName, userRoles, userPermissions, userDepartment, onCreated, onClose }: Props) {
  const privileged = userRoles.includes('admin') || userRoles.includes('it_admin');
  const canServices = privileged || userPermissions.includes('create_services');
  const canItems = privileged || userPermissions.includes('create_items');
  const allowed = kind === 'service' ? canServices : kind === 'pharmacy' ? canItems : canItems || canServices;
  const [name, setName] = useState(initialName);
  const [code, setCode] = useState('');
  const [department, setDepartment] = useState(userDepartment ?? '');
  const [unit, setUnit] = useState('unit');
  const [amount, setAmount] = useState('0');
  const [category, setCategory] = useState('');
  const [specimen, setSpecimen] = useState('');
  const [strength, setStrength] = useState('');
  const [form, setForm] = useState('');
  const [generic, setGeneric] = useState('');
  const [referenceText, setReferenceText] = useState('');
  const [referenceLow, setReferenceLow] = useState('');
  const [referenceHigh, setReferenceHigh] = useState('');
  const [turnaround, setTurnaround] = useState('60');
  const [saving, setSaving] = useState(false);

  if (!allowed) return null;

  const title = kind === 'service' ? 'Create service' : kind === 'pharmacy' ? 'Create medication / pharmacy item' : 'Create laboratory test';
  const save = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!name.trim()) return toast({ title: 'Name required', description: 'Enter a name before saving.', variant: 'destructive' });
    setSaving(true);
    let data: any = null;
    let error: any = null;
    if (kind === 'service') {
      ({ data, error } = await supabase.rpc('create_service_catalogue_item' as never, {
        _service_code: code, _service_name: name, _department: department, _unit: unit,
        _amount: Number(amount), _currency: 'GHS',
      } as never));
    } else if (kind === 'pharmacy') {
      ({ data, error } = await supabase.rpc('create_pharmacy_inventory_item' as never, {
        _drug_name: name, _brand_name: '', _generic_name: generic, _strength: strength, _form: form,
        _supplier: '', _batch_number: '', _expiry_date: null, _stock_quantity: 0, _reorder_level: 0, _unit_price: 0,
      } as never));
    } else {
      ({ data, error } = await supabase.rpc('create_lab_test_catalogue_item' as never, {
        _test_code: code, _test_name: name, _category: category, _specimen_type: specimen, _unit: unit,
        _reference_low: referenceLow === '' ? null : Number(referenceLow),
        _reference_high: referenceHigh === '' ? null : Number(referenceHigh),
        _reference_text: referenceText, _default_charge: Number(amount), _turnaround_minutes: Number(turnaround),
      } as never));
    }
    setSaving(false);
    if (error) return toast({ title: 'Could not create catalogue entry', description: error.message, variant: 'destructive' });
    playSuccess();
    onCreated(data);
    onClose();
  };

  return <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" role="dialog" aria-modal="true" aria-label={title}>
    <form onSubmit={save} className="card-medical w-full max-w-lg max-h-[90vh] overflow-y-auto p-5 space-y-3 bg-background">
      <div className="flex items-center justify-between gap-3"><div><h2 className="font-semibold">{title}</h2><p className="text-xs text-muted-foreground">This will update the shared master catalogue.</p></div><button type="button" onClick={onClose} className="btn-ghost" aria-label="Close"><X className="w-4 h-4" /></button></div>
      <input autoFocus value={name} onChange={e => setName(e.target.value)} className="input-medical w-full" placeholder={kind === 'service' ? 'Service name' : kind === 'pharmacy' ? 'Medication / item name' : 'Laboratory test name'} />
      {(kind === 'service' || kind === 'lab') && <input value={code} onChange={e => setCode(e.target.value)} className="input-medical w-full" placeholder={kind === 'service' ? 'Service code' : 'Test code'} />}
      {kind === 'service' && <><input value={department} onChange={e => setDepartment(e.target.value)} disabled={!privileged} className="input-medical w-full disabled:opacity-60" placeholder="Department" /><input value={unit} onChange={e => setUnit(e.target.value)} className="input-medical w-full" placeholder="Unit" /><input value={amount} onChange={e => setAmount(e.target.value)} type="number" min="0" step="0.01" className="input-medical w-full" placeholder="Charge (GHS)" /></>}
      {kind === 'pharmacy' && <><input value={generic} onChange={e => setGeneric(e.target.value)} className="input-medical w-full" placeholder="Generic name" /><div className="grid grid-cols-2 gap-2"><input value={strength} onChange={e => setStrength(e.target.value)} className="input-medical w-full" placeholder="Strength" /><input value={form} onChange={e => setForm(e.target.value)} className="input-medical w-full" placeholder="Dosage form" /></div><p className="text-xs text-muted-foreground">Initial stock is zero. Add supplier, batch, expiry, price and stock from the pharmacy store workflow.</p></>}
      {kind === 'lab' && <><input value={category} onChange={e => setCategory(e.target.value)} className="input-medical w-full" placeholder="Category" /><input value={specimen} onChange={e => setSpecimen(e.target.value)} className="input-medical w-full" placeholder="Specimen type" /><div className="grid grid-cols-2 gap-2"><input value={unit} onChange={e => setUnit(e.target.value)} className="input-medical w-full" placeholder="Unit" /><input value={amount} onChange={e => setAmount(e.target.value)} type="number" min="0" step="0.01" className="input-medical w-full" placeholder="Default charge (GHS)" /></div><div className="grid grid-cols-2 gap-2"><input value={referenceLow} onChange={e => setReferenceLow(e.target.value)} type="number" className="input-medical w-full" placeholder="Reference low" /><input value={referenceHigh} onChange={e => setReferenceHigh(e.target.value)} type="number" className="input-medical w-full" placeholder="Reference high" /></div><input value={referenceText} onChange={e => setReferenceText(e.target.value)} className="input-medical w-full" placeholder="Reference text" /><input value={turnaround} onChange={e => setTurnaround(e.target.value)} type="number" min="0" className="input-medical w-full" placeholder="Turnaround minutes" /></>}
      <div className="flex justify-end gap-2 pt-2"><button type="button" onClick={onClose} className="btn-secondary">Cancel</button><button disabled={saving} className="btn-primary inline-flex items-center gap-2"><Plus className="w-4 h-4" />{saving ? 'Saving…' : 'Create and use'}</button></div>
    </form>
  </div>;
}

function playSuccess() { /* page-level workflow sound is optional; the database mutation is authoritative */ }
