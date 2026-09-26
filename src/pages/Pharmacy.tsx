import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AlertTriangle, BellRing, CreditCard, Package, Pill, RefreshCw, Search, ShoppingCart } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Link } from 'react-router-dom';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { useAuth } from '@/contexts/AuthContext';
import CatalogueCreateModal from '@/components/catalogue/CatalogueCreateModal';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';

type Patient = { id: string; first_name: string; last_name: string; patient_code: string };
type InventoryItem = { id: string; drug_name: string; brand_name: string | null; generic_name: string | null; form: string | null; strength: string | null; stock_quantity: number; reorder_level: number; unit_price: number; supplier: string | null; batch_number: string | null; expiry_date: string | null };
type Prescription = { id: string; patient_id: string; medication: string; dosage: string | null; frequency: string | null; duration: string | null; computed_quantity: number | null; status: string; patients?: Patient };
type Plan = { id: string; medication_name: string; prepared_quantity: number; service_order_id: string | null; service_order_status?: string | null; patients?: Patient };
type Alternative = Pick<InventoryItem, 'id' | 'drug_name' | 'brand_name' | 'generic_name' | 'strength' | 'form' | 'supplier' | 'stock_quantity' | 'unit_price'>;
type PosSale = { id: string; medication: string; quantity: number; total_amount: number; status: string; service_order_id: string | null };
const db = supabase as any;

export default function Pharmacy() {
  const { user } = useAuth();
  const [tab, setTab] = useState<'dispense' | 'pos' | 'inventory'>('dispense');
  const [patients, setPatients] = useState<Patient[]>([]);
  const [inventory, setInventory] = useState<InventoryItem[]>([]);
  const [prescriptions, setPrescriptions] = useState<Prescription[]>([]);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [posSales, setPosSales] = useState<PosSale[]>([]);
  const [alternatives, setAlternatives] = useState<Record<string, Alternative[]>>({});
  const [patientId, setPatientId] = useState('');
  const [search, setSearch] = useState('');
  const [matches, setMatches] = useState<Record<string, string>>({});
  const [quantities, setQuantities] = useState<Record<string, number>>({});
  const [posItem, setPosItem] = useState('');
  const [posPatient, setPosPatient] = useState('');
  const [posQuantity, setPosQuantity] = useState(1);
  const [loading, setLoading] = useState(false);
  const [createMedicationName, setCreateMedicationName] = useState('');
  const [inventoryForm, setInventoryForm] = useState({ drug_name: '', brand_name: '', generic_name: '', strength: '', form: '', supplier: '', batch_number: '', expiry_date: '', stock_quantity: 0, reorder_level: 20, unit_price: 0 });
  const previousActive = useRef(0);
  const loadedActive = useRef(false);

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await db.rpc('get_pharmacy_workspace', { _limit: 300 });
    if (error) {
      setLoading(false);
      toast.error(error.message);
      return;
    }
    const workspace = (data ?? {}) as {
      patients?: Patient[];
      inventory?: InventoryItem[];
      prescriptions?: Prescription[];
      plans?: Plan[];
      pos_sales?: PosSale[];
    };
    setPatients(workspace.patients ?? []);
    setInventory(workspace.inventory ?? []);
    setPrescriptions(workspace.prescriptions ?? []);
    setPlans(workspace.plans ?? []);
    setPosSales((workspace.pos_sales ?? []).map((sale) => ({
      ...sale,
      status: sale.status,
    })));
    setLoading(false);
  }, []);

  useEffect(() => {
    void load();
    const refreshTimer = window.setInterval(() => void load(), 30000);
    return () => window.clearInterval(refreshTimer);
  }, [load]);

  const visiblePrescriptions = useMemo(() => prescriptions.filter((item) => !patientId || item.patient_id === patientId), [patientId, prescriptions]);
  const visibleInventory = useMemo(() => inventory.filter((item) => `${item.drug_name} ${item.brand_name ?? ''} ${item.generic_name ?? ''} ${item.supplier ?? ''}`.toLowerCase().includes(search.toLowerCase())), [inventory, search]);
  const counters = useMemo(() => {
    const awaitingPreparation = prescriptions.length;
    const awaitingRelease = plans.filter((plan) => !['released', 'in_progress', 'completed'].includes(plan.service_order_status ?? '')).length;
    const readyToDispense = plans.filter((plan) => ['released', 'in_progress'].includes(plan.service_order_status ?? '')).length;
    const posAwaitingRelease = posSales.filter((sale) => !['released', 'in_progress', 'dispensed'].includes(sale.status)).length;
    const lowStock = inventory.filter((item) => item.stock_quantity <= item.reorder_level).length;
    const active = awaitingPreparation + awaitingRelease + readyToDispense + posAwaitingRelease;
    if (loadedActive.current && active > previousActive.current) playWorkflowSound('info');
    previousActive.current = active; loadedActive.current = true;
    return { awaitingPreparation, awaitingRelease, readyToDispense, posAwaitingRelease, lowStock };
  }, [prescriptions, plans, posSales, inventory]);

  const findAlternatives = async (prescription: Prescription) => { const { data, error } = await db.rpc('find_pharmacy_alternatives', { _medication: prescription.medication, _strength: prescription.dosage }); if (error) return toast.error(error.message); setAlternatives((current) => ({ ...current, [prescription.id]: (data ?? []) as Alternative[] })); };
  const canCreateItems = user?.roles.some((role) => role === 'admin' || role === 'it_admin') || user?.permissions.includes('create_items');
  const prepare = async (prescription: Prescription) => { const inventoryId = matches[prescription.id]; if (!inventoryId) return toast.error('Select the available product or an approved alternative.'); const { error } = await db.rpc('prepare_pharmacy_dispensing', { _prescription_id: prescription.id, _inventory_id: inventoryId, _quantity: Math.max(1, quantities[prescription.id] ?? prescription.computed_quantity ?? 1), _notes: null }); if (error) { playWorkflowSound('error'); return toast.error(error.message); } playWorkflowSound('success'); toast.success('Prescription prepared. Accounts must receive payment before dispensing.'); void load(); };
  const dispense = async (plan: Plan) => { const { error } = await db.rpc('confirm_pharmacy_dispense', { _plan_id: plan.id }); if (error) { playWorkflowSound('error'); return toast.error(error.message); } playWorkflowSound('success'); toast.success(`${plan.medication_name} dispensed.`); void load(); };
  const createPosSale = async (event: React.FormEvent) => { event.preventDefault(); if (!posItem || posQuantity < 1) return toast.error('Select a product and quantity.'); const { error } = await db.rpc('create_pharmacy_pos_sale', { _patient_id: posPatient || null, _inventory_id: posItem, _quantity: posQuantity }); if (error) { playWorkflowSound('error'); return toast.error(error.message); } playWorkflowSound('success'); toast.success('Walk-in sale created and sent for payment release.'); setPosItem(''); setPosPatient(''); setPosQuantity(1); void load(); };
  const addInventory = async (event: React.FormEvent) => { event.preventDefault(); if (!inventoryForm.drug_name.trim()) return toast.error('Drug name is required.'); const { error } = await db.rpc('create_pharmacy_inventory_item', { _drug_name: inventoryForm.drug_name, _brand_name: inventoryForm.brand_name || null, _generic_name: inventoryForm.generic_name || null, _strength: inventoryForm.strength || null, _form: inventoryForm.form || null, _supplier: inventoryForm.supplier || null, _batch_number: inventoryForm.batch_number || null, _expiry_date: inventoryForm.expiry_date || null, _stock_quantity: inventoryForm.stock_quantity, _reorder_level: inventoryForm.reorder_level, _unit_price: inventoryForm.unit_price }); if (error) { playWorkflowSound('error'); return toast.error(error.message); } playWorkflowSound('success'); toast.success('Product added to the pharmacy store.'); setInventoryForm({ drug_name: '', brand_name: '', generic_name: '', strength: '', form: '', supplier: '', batch_number: '', expiry_date: '', stock_quantity: 0, reorder_level: 20, unit_price: 0 }); void load(); };

  const counterCards = [
    { label: 'Prescriptions waiting', value: counters.awaitingPreparation, surface: 'bg-primary/5', tone: 'text-primary', tab: 'dispense' as const, urgent: counters.awaitingPreparation > 0 },
    { label: 'Awaiting Accounts release', value: counters.awaitingRelease, surface: 'bg-warning/5', tone: 'text-warning', tab: 'dispense' as const, urgent: counters.awaitingRelease > 0 },
    { label: 'Ready to dispense', value: counters.readyToDispense, surface: 'bg-success/5', tone: 'text-success', tab: 'dispense' as const, urgent: counters.readyToDispense > 0 },
    { label: 'POS payment queue', value: counters.posAwaitingRelease, surface: 'bg-info/5', tone: 'text-info', tab: 'pos' as const, urgent: counters.posAwaitingRelease > 0 },
    { label: 'Low-stock products', value: counters.lowStock, surface: 'bg-critical/5', tone: 'text-critical', tab: 'inventory' as const, urgent: counters.lowStock > 0 },
  ];

  return (
    <OperationalWorklistShell
      icon={Pill}
      eyebrow="Diagnostics & Medicines · Pharmacy"
      title="Pharmacy Workspace"
      description="Prepare prescriptions, release paid orders, dispense medicines, manage walk-in sales and monitor pharmacy stock from one operational workspace."
      actions={(
        <>
          <Link to="/notifications" className="btn-ghost inline-flex items-center gap-2"><BellRing className="w-4 h-4" aria-hidden="true" /> Notifications</Link>
          <button type="button" onClick={() => void load()} disabled={loading} className="btn-secondary inline-flex items-center gap-2" aria-label="Refresh pharmacy workspace">
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} aria-hidden="true" /> {loading ? 'Refreshing…' : 'Refresh'}
          </button>
        </>
      )}
      counters={counterCards.map((card) => ({ label: card.label, value: card.value, surface: card.surface, tone: card.tone }))}
      beforeList={(
        <>
          <div className="rounded-xl border border-primary/20 bg-primary/5 p-3 flex gap-2 text-sm">
            <CreditCard className="w-4 h-4 text-primary mt-0.5 shrink-0" aria-hidden="true" />
            <p className="text-muted-foreground">Preparation never reduces stock. Stock is committed only after Accounts releases the service order and the pharmacist confirms dispensing.</p>
          </div>
          {counters.lowStock > 0 && (
            <div className="rounded-xl border border-warning/40 bg-warning/5 p-3 flex gap-2 text-sm" role="status">
              <AlertTriangle className="w-4 h-4 text-warning mt-0.5 shrink-0" aria-hidden="true" />
              <p className="text-muted-foreground">{counters.lowStock} product{counters.lowStock === 1 ? '' : 's'} are at or below reorder level. Review the pharmacy store.</p>
            </div>
          )}
          <div className="flex flex-wrap gap-2 border-b border-border" role="tablist" aria-label="Pharmacy workspaces">
            {(['dispense', 'pos', 'inventory'] as const).map((value) => (
              <button
                key={value}
                type="button"
                role="tab"
                aria-selected={tab === value}
                tabIndex={tab === value ? 0 : -1}
                onClick={() => setTab(value)}
                className={`px-4 py-2 border-b-2 text-sm ${tab === value ? 'border-primary text-primary font-medium' : 'border-transparent text-muted-foreground hover:text-foreground'}`}
              >
                {value === 'pos' ? 'Walk-in POS' : value === 'inventory' ? 'Pharmacy store' : 'Prescription dispensing'}
              </button>
            ))}
          </div>
        </>
      )}
      listTitle={tab === 'dispense' ? 'Prescription dispensing worklist' : tab === 'pos' ? 'Walk-in POS worklist' : 'Pharmacy inventory worklist'}
      listDescription={tab === 'dispense' ? 'Prepare prescriptions and dispense only after the authoritative payment/release state permits it.' : tab === 'pos' ? 'Create walk-in payment orders and dispense only after Accounts releases them.' : 'Search pharmacy stock, identify reorder risks and add authorised store items.'}
      listMeta={tab === 'dispense' ? `${visiblePrescriptions.length + plans.length} dispensing record${visiblePrescriptions.length + plans.length === 1 ? '' : 's'}` : tab === 'pos' ? `${posSales.length} POS sale${posSales.length === 1 ? '' : 's'}` : `${visibleInventory.length} stock item${visibleInventory.length === 1 ? '' : 's'}`}
      loading={loading}
      empty={
        tab === 'dispense'
          ? visiblePrescriptions.length === 0 && plans.length === 0
          : tab === 'pos'
            ? posSales.length === 0
            : visibleInventory.length === 0
      }
      emptyTitle={tab === 'dispense' ? 'No dispensing records' : tab === 'pos' ? 'No POS sales' : 'No pharmacy stock matches'}
      emptyDescription={tab === 'dispense' ? 'Active prescriptions and prepared orders will appear here.' : tab === 'pos' ? 'Create a walk-in payment order to begin.' : 'Adjust the search or add an authorised store item.'}
    >
      {tab === 'dispense' && (
        <>
          <div className="p-4 border-b border-border">
            <label htmlFor="pharmacy-patient-filter" className="text-xs font-semibold block max-w-xl">
              Filter by patient
              <select id="pharmacy-patient-filter" value={patientId} onChange={(event) => setPatientId(event.target.value)} className="input-medical w-full mt-1">
                <option value="">All active prescriptions</option>
                {patients.map((patient) => <option key={patient.id} value={patient.id}>{patient.first_name} {patient.last_name} · {patient.patient_code}</option>)}
              </select>
            </label>
          </div>
          {visiblePrescriptions.map((prescription) => {
            const choices = alternatives[prescription.id] ?? [];
            return (
              <article key={prescription.id} className="p-5 space-y-3">
                <div className="flex flex-col gap-3 sm:flex-row sm:justify-between">
                  <div className="min-w-0">
                    <h2 className="font-semibold">{prescription.medication}</h2>
                    <p className="text-sm text-muted-foreground">{prescription.patients ? `${prescription.patients.first_name} ${prescription.patients.last_name}` : 'Patient'} · {prescription.dosage ?? 'Dose not specified'} · {prescription.frequency ?? 'Frequency not specified'} · {prescription.status}</p>
                  </div>
                  <button type="button" onClick={() => void findAlternatives(prescription)} className="btn-secondary text-sm shrink-0">Find alternatives</button>
                </div>
                <div className="grid gap-3 md:grid-cols-[1fr_120px_auto]">
                  <label className="sr-only" htmlFor={`pharmacy-product-${prescription.id}`}>Product for {prescription.medication}</label>
                  <select id={`pharmacy-product-${prescription.id}`} value={matches[prescription.id] ?? ''} onChange={(event) => setMatches((current) => ({ ...current, [prescription.id]: event.target.value }))} className="input-medical">
                    <option value="">Select product / supplier</option>
                    {choices.map((item) => <option key={item.id} value={item.id}>{item.drug_name} · {item.supplier ?? 'In store'} · {item.stock_quantity} in stock</option>)}
                    {inventory.filter((item) => item.stock_quantity > 0 && item.drug_name.toLowerCase().includes(prescription.medication.toLowerCase())).map((item) => <option key={item.id} value={item.id}>{item.drug_name} · {item.supplier ?? 'In store'} · {item.stock_quantity} in stock</option>)}
                  </select>
                  <label className="sr-only" htmlFor={`pharmacy-quantity-${prescription.id}`}>Quantity for {prescription.medication}</label>
                  <input id={`pharmacy-quantity-${prescription.id}`} type="number" min="1" value={quantities[prescription.id] ?? prescription.computed_quantity ?? 1} onChange={(event) => setQuantities((current) => ({ ...current, [prescription.id]: Number(event.target.value) }))} className="input-medical" />
                  <button type="button" onClick={() => void prepare(prescription)} className="btn-primary">Prepare</button>
                </div>
                {choices.length > 0 && <p className="text-xs text-success">Available alternatives are shown by brand, supplier and current stock.</p>}
                {canCreateItems && inventory.filter((item) => item.drug_name.toLowerCase().includes(prescription.medication.toLowerCase())).length === 0 && <button type="button" onClick={() => setCreateMedicationName(prescription.medication)} className="btn-secondary text-sm">Add {prescription.medication}</button>}
              </article>
            );
          })}
          {plans.map((plan) => (
            <article key={plan.id} className="p-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
              <div>
                <p className="font-medium">{plan.medication_name} · {plan.prepared_quantity}</p>
                <p className="text-xs text-muted-foreground">{plan.patients ? `${plan.patients.first_name} ${plan.patients.last_name}` : 'Patient'} · {plan.service_order_status ?? 'awaiting release'}</p>
              </div>
              <button type="button" disabled={!['released', 'in_progress'].includes(plan.service_order_status ?? '')} onClick={() => void dispense(plan)} className="btn-primary disabled:opacity-50">Dispense</button>
            </article>
          ))}
        </>
      )}
      {tab === 'pos' && (
        <>
          <div className="p-5 border-b border-border">
            <form onSubmit={createPosSale} className="grid gap-3 md:grid-cols-4">
              <div>
                <label htmlFor="pos-patient" className="text-xs font-semibold block">Patient</label>
                <select id="pos-patient" value={posPatient} onChange={(event) => setPosPatient(event.target.value)} className="input-medical w-full mt-1"><option value="">Walk-in / no patient record</option>{patients.map((patient) => <option key={patient.id} value={patient.id}>{patient.first_name} {patient.last_name} · {patient.patient_code}</option>)}</select>
              </div>
              <div className="md:col-span-2">
                <label htmlFor="pos-item" className="text-xs font-semibold block">Medication</label>
                <select id="pos-item" value={posItem} onChange={(event) => setPosItem(event.target.value)} className="input-medical w-full mt-1"><option value="">Select in-stock medication</option>{inventory.filter((item) => item.stock_quantity > 0).map((item) => <option key={item.id} value={item.id}>{item.drug_name} · {item.stock_quantity} in stock · GHS {item.unit_price}</option>)}</select>
              </div>
              <div>
                <label htmlFor="pos-quantity" className="text-xs font-semibold block">Quantity</label>
                <input id="pos-quantity" type="number" min="1" value={posQuantity} onChange={(event) => setPosQuantity(Number(event.target.value))} className="input-medical w-full mt-1" />
              </div>
              <div className="md:col-span-4 flex justify-end"><button type="submit" className="btn-primary inline-flex items-center gap-2"><ShoppingCart className="w-4 h-4" aria-hidden="true" /> Create payment order</button></div>
            </form>
          </div>
          {posSales.map((sale) => (
            <article key={sale.id} className="p-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
              <div><p className="font-medium">{sale.medication} · {sale.quantity}</p><p className="text-xs text-muted-foreground">GHS {sale.total_amount} · {sale.status}</p></div>
              <button type="button" disabled={!['released', 'in_progress'].includes(sale.status)} onClick={async () => { const { error } = await db.rpc('confirm_pharmacy_pos_sale', { _sale_id: sale.id }); if (error) { playWorkflowSound('error'); return toast.error(error.message); } playWorkflowSound('success'); toast.success('Walk-in medication dispensed.'); void load(); }} className="btn-primary disabled:opacity-50">Dispense</button>
            </article>
          ))}
        </>
      )}
      {tab === 'inventory' && (
        <>
          <div className="p-5 border-b border-border">
            <form onSubmit={addInventory} className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
              {(['drug_name', 'brand_name', 'generic_name', 'strength', 'form', 'supplier', 'batch_number', 'expiry_date'] as const).map((field) => (
                <div key={field}>
                  <label htmlFor={`inventory-${field}`} className="text-xs font-semibold block capitalize">{field.replace('_', ' ')}</label>
                  <input id={`inventory-${field}`} value={inventoryForm[field]} onChange={(event) => setInventoryForm((current) => ({ ...current, [field]: event.target.value }))} type={field === 'expiry_date' ? 'date' : 'text'} className="input-medical w-full mt-1" />
                </div>
              ))}
              <div><label htmlFor="inventory-stock" className="text-xs font-semibold block">Stock quantity</label><input id="inventory-stock" type="number" min="0" value={inventoryForm.stock_quantity} onChange={(event) => setInventoryForm((current) => ({ ...current, stock_quantity: Number(event.target.value) }))} className="input-medical w-full mt-1" /></div>
              <div><label htmlFor="inventory-reorder" className="text-xs font-semibold block">Reorder level</label><input id="inventory-reorder" type="number" min="0" value={inventoryForm.reorder_level} onChange={(event) => setInventoryForm((current) => ({ ...current, reorder_level: Number(event.target.value) }))} className="input-medical w-full mt-1" /></div>
              <div><label htmlFor="inventory-price" className="text-xs font-semibold block">Unit price</label><input id="inventory-price" type="number" min="0" step="0.01" value={inventoryForm.unit_price} onChange={(event) => setInventoryForm((current) => ({ ...current, unit_price: Number(event.target.value) }))} className="input-medical w-full mt-1" /></div>
              <div className="md:col-span-2 lg:col-span-4 flex justify-end"><button type="submit" className="btn-primary inline-flex items-center gap-2"><Package className="w-4 h-4" aria-hidden="true" /> Add to store</button></div>
            </form>
          </div>
          <div className="p-4 border-b border-border">
            <label htmlFor="pharmacy-stock-search" className="sr-only">Search pharmacy stock</label>
            <div className="relative"><Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" aria-hidden="true" /><input id="pharmacy-stock-search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search product, brand or supplier" className="input-medical pl-9 w-full" /></div>
          </div>
          {visibleInventory.map((item) => (
            <article key={item.id} className={`p-4 flex flex-col sm:flex-row sm:justify-between gap-3 ${item.stock_quantity <= item.reorder_level ? 'bg-warning/5' : ''}`}>
              <div><p className="font-medium">{item.drug_name}{item.brand_name ? ` · ${item.brand_name}` : ''}</p><p className="text-xs text-muted-foreground">{item.generic_name ?? 'Generic not recorded'} · {item.strength ?? 'Strength not recorded'} · {item.supplier ?? 'Supplier not recorded'}</p></div>
              <div className="text-left sm:text-right text-sm"><p>{item.stock_quantity} in stock</p><p className="text-xs text-muted-foreground">GHS {item.unit_price} · reorder {item.reorder_level}</p></div>
            </article>
          ))}
        </>
      )}
    </OperationalWorklistShell>
  );
  {createMedicationName && <CatalogueCreateModal kind="pharmacy" initialName={createMedicationName} userRoles={user?.roles ?? []} userPermissions={user?.permissions ?? []} userDepartment={user?.department} onCreated={() => void load()} onClose={() => setCreateMedicationName('')} />}
  </div>;
}
