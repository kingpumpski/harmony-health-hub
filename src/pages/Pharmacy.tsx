import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AlertTriangle, BellRing, CreditCard, Package, Pencil, Pill, RefreshCw, Search, ShoppingCart, Settings2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { Link } from 'react-router-dom';
import { playWorkflowSound } from '@/lib/workflowFeedback';
import { useAuth } from '@/contexts/AuthContext';
import CatalogueCreateModal from '@/components/catalogue/CatalogueCreateModal';
import OperationalWorklistShell from '@/components/workflow/OperationalWorklistShell';
import ClinicalDataTable, { ClinicalStatusBadge, ClinicalTableAction } from '@/components/workflow/ClinicalDataTable';

type Patient = { id: string; first_name: string; last_name: string; patient_code: string };
type InventoryItem = { id: string; drug_name: string; brand_name: string | null; generic_name: string | null; form: string | null; strength: string | null; stock_quantity: number; reorder_level: number; unit_price: number; supplier: string | null; batch_number: string | null; expiry_date: string | null };
type Prescription = { id: string; patient_id: string; created_at?: string; medication: string; dosage: string | null; frequency: string | null; duration: string | null; computed_quantity: number | null; status: string; patients?: Patient };
type Plan = { id: string; created_at?: string; medication_name: string; prepared_quantity: number; service_order_id: string | null; service_order_status?: string | null; patients?: Patient };
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
  const [editingInventoryId, setEditingInventoryId] = useState<string | null>(null);
  const [inventoryForm, setInventoryForm] = useState({ drug_name: '', brand_name: '', generic_name: '', strength: '', form: '', supplier: '', batch_number: '', expiry_date: '', stock_quantity: 0, reorder_level: 20, unit_price: 0 });
  const previousActive = useRef(0);
  const loadedActive = useRef(false);
  const [dispenseStatusFilter, setDispenseStatusFilter] = useState('all');
  const [posStatusFilter, setPosStatusFilter] = useState('all');
  const [inventoryStockFilter, setInventoryStockFilter] = useState('all');
  const [appliedDispenseStatus, setAppliedDispenseStatus] = useState('all');
  const [appliedPosStatus, setAppliedPosStatus] = useState('all');
  const [appliedInventoryStock, setAppliedInventoryStock] = useState('all');
  const [expandedPrescriptionId, setExpandedPrescriptionId] = useState<string | null>(null);
  const [expandedPosId, setExpandedPosId] = useState<string | null>(null);
  const [prescriptionColumns, setPrescriptionColumns] = useState({ medication: false, dosage: false, status: false });
  const [columnsOpen, setColumnsOpen] = useState(false);

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
  const canCreateItems = user?.roles.some((role) => role === 'admin' || role === 'it_admin' || role === 'pharmacist') || user?.permissions.includes('create_items');
  const prepare = async (prescription: Prescription) => { const inventoryId = matches[prescription.id]; if (!inventoryId) return toast.error('Select the available product or an approved alternative.'); const { error } = await db.rpc('prepare_pharmacy_dispensing', { _prescription_id: prescription.id, _inventory_id: inventoryId, _quantity: Math.max(1, quantities[prescription.id] ?? prescription.computed_quantity ?? 1), _notes: null }); if (error) { playWorkflowSound('error'); return toast.error(error.message); } playWorkflowSound('success'); toast.success('Prescription prepared. Accounts must receive payment before dispensing.'); void load(); };
  const dispense = async (plan: Plan) => { const { error } = await db.rpc('confirm_pharmacy_dispense', { _plan_id: plan.id }); if (error) { playWorkflowSound('error'); return toast.error(error.message); } playWorkflowSound('success'); toast.success(`${plan.medication_name} dispensed.`); void load(); };
  const createPosSale = async (event: React.FormEvent) => { event.preventDefault(); if (!posItem || posQuantity < 1) return toast.error('Select a product and quantity.'); const { error } = await db.rpc('create_pharmacy_pos_sale', { _patient_id: posPatient || null, _inventory_id: posItem, _quantity: posQuantity }); if (error) { playWorkflowSound('error'); return toast.error(error.message); } playWorkflowSound('success'); toast.success('Walk-in sale created and sent for payment release.'); setPosItem(''); setPosPatient(''); setPosQuantity(1); void load(); };
  const resetInventoryForm = () => {
    setEditingInventoryId(null);
    setInventoryForm({ drug_name: '', brand_name: '', generic_name: '', strength: '', form: '', supplier: '', batch_number: '', expiry_date: '', stock_quantity: 0, reorder_level: 20, unit_price: 0 });
  };
  const editInventoryItem = (item: InventoryItem) => {
    setEditingInventoryId(item.id);
    setInventoryForm({
      drug_name: item.drug_name ?? '', brand_name: item.brand_name ?? '', generic_name: item.generic_name ?? '',
      strength: item.strength ?? '', form: item.form ?? '', supplier: item.supplier ?? '', batch_number: item.batch_number ?? '',
      expiry_date: item.expiry_date ?? '', stock_quantity: Number(item.stock_quantity ?? 0),
      reorder_level: Number(item.reorder_level ?? 0), unit_price: Number(item.unit_price ?? 0),
    });
  };
  const saveInventory = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!inventoryForm.drug_name.trim()) return toast.error('Drug name is required.');
    const payload = {
      _drug_name: inventoryForm.drug_name, _brand_name: inventoryForm.brand_name || null,
      _generic_name: inventoryForm.generic_name || null, _strength: inventoryForm.strength || null,
      _form: inventoryForm.form || null, _supplier: inventoryForm.supplier || null,
      _batch_number: inventoryForm.batch_number || null, _expiry_date: inventoryForm.expiry_date || null,
      _stock_quantity: inventoryForm.stock_quantity, _reorder_level: inventoryForm.reorder_level,
      _unit_price: inventoryForm.unit_price,
    };
    const { error } = editingInventoryId
      ? await db.rpc('update_pharmacy_inventory_item', { _item_id: editingInventoryId, ...payload })
      : await db.rpc('create_pharmacy_inventory_item', payload);
    if (error) { playWorkflowSound('error'); return toast.error(error.message); }
    playWorkflowSound('success');
    toast.success(editingInventoryId ? 'Pharmacy item updated.' : 'Product added to the pharmacy store.');
    resetInventoryForm();
    void load();
  };

  const counterCards = [
    { label: 'Prescriptions waiting', value: counters.awaitingPreparation, surface: 'bg-primary/5', tone: 'text-primary', tab: 'dispense' as const, urgent: counters.awaitingPreparation > 0 },
    { label: 'Awaiting Accounts release', value: counters.awaitingRelease, surface: 'bg-warning/5', tone: 'text-warning', tab: 'dispense' as const, urgent: counters.awaitingRelease > 0 },
    { label: 'Ready to dispense', value: counters.readyToDispense, surface: 'bg-success/5', tone: 'text-success', tab: 'dispense' as const, urgent: counters.readyToDispense > 0 },
    { label: 'POS payment queue', value: counters.posAwaitingRelease, surface: 'bg-info/5', tone: 'text-info', tab: 'pos' as const, urgent: counters.posAwaitingRelease > 0 },
    { label: 'Low-stock products', value: counters.lowStock, surface: 'bg-critical/5', tone: 'text-critical', tab: 'inventory' as const, urgent: counters.lowStock > 0 },
  ];

  return (
    <>
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
      listDescription={tab === 'dispense' ? 'Prepare prescriptions and dispense only after the authoritative payment/release state permits it.' : tab === 'pos' ? 'Create walk-in payment orders and dispense only after Accounts releases them.' : 'Search pharmacy stock, identify reorder risks and manage authorised store items.'}
      listMeta={tab === 'dispense' ? `${visiblePrescriptions.length + plans.length} dispensing record${visiblePrescriptions.length + plans.length === 1 ? '' : 's'}` : tab === 'pos' ? `${posSales.length} POS sale${posSales.length === 1 ? '' : 's'}` : `${visibleInventory.length} stock item${visibleInventory.length === 1 ? '' : 's'}`}
      loading={false}
      empty={false}
      listContent={(
        <div>
          {tab === 'dispense' && (
            <>
            <div className="relative mb-2 flex justify-end">
              <button type="button" className="btn-ghost inline-flex items-center gap-2 text-xs" aria-expanded={columnsOpen} onClick={() => setColumnsOpen((open) => !open)}><Settings2 className="h-4 w-4" aria-hidden="true" /> Columns</button>
              {columnsOpen && <div className="absolute right-0 top-10 z-20 w-56 rounded-lg border border-border bg-background p-3 shadow-lg">
                {Object.entries({ medication: 'Medication', dosage: 'Dosage / frequency', status: 'Status' }).map(([key,label]) => <label key={key} className="flex items-center gap-2 py-1 text-xs"><input type="checkbox" checked={Boolean(prescriptionColumns[key as keyof typeof prescriptionColumns])} onChange={() => setPrescriptionColumns((current) => ({ ...current, [key]: !current[key as keyof typeof current] }))} />{label}</label>)}
              </div>}
            </div>
            <ClinicalDataTable
              title="Prescription dispensing"
              description="Patient ID, patient name and timestamp remain visible by default. Optional clinical columns can be enabled without changing the operational workflow."
              meta={`${visiblePrescriptions.length} prescriptions · ${plans.length} prepared`}
              filters={[
                { label: 'Patient', value: patientId, onChange: setPatientId, options: [{ value: '', label: 'All active prescriptions' }, ...patients.map((patient) => ({ value: patient.id, label: `${patient.first_name} ${patient.last_name} · ${patient.patient_code}` }))] },
                { label: 'Preparation state', value: dispenseStatusFilter, onChange: setDispenseStatusFilter, options: [{ value: 'all', label: 'All states' }, { value: 'prescription', label: 'Awaiting preparation' }, { value: 'ready', label: 'Ready to dispense' }] },
              ]}
              onSearch={() => setAppliedDispenseStatus(dispenseStatusFilter)}
              loading={loading}
              empty={false}
            >
              <thead>
                <tr>
                  <th scope="col">No.</th><th scope="col">Patient ID</th><th scope="col">Full Name</th><th scope="col">Timestamp</th>
                  {prescriptionColumns.medication && <th scope="col">Medication</th>}{prescriptionColumns.dosage && <th scope="col">Dosage</th>}{prescriptionColumns.status && <th scope="col">Status</th>}
                  <th scope="col" className="text-right">Action</th>
                </tr>
              </thead>
              <tbody>
                {visiblePrescriptions.filter((prescription) => appliedDispenseStatus === 'all' || appliedDispenseStatus === 'prescription').map((prescription) => {
                  const choices = alternatives[prescription.id] ?? [];
                  return (
                    <Fragment key={prescription.id}>
                      <tr>
                    <td>{visiblePrescriptions.indexOf(prescription) + 1}</td><td className="font-mono text-xs">{prescription.patients?.patient_code ?? prescription.patient_id.slice(0, 8)}</td><td><p className="font-semibold">{prescription.patients ? `${prescription.patients.first_name} ${prescription.patients.last_name}` : 'Patient'}</p></td><td className="whitespace-nowrap text-xs text-muted-foreground">{new Date(prescription.created_at ?? Date.now()).toLocaleString()}</td>
                    {prescriptionColumns.medication && <td><p className="font-medium">{prescription.medication}</p><p className="text-xs text-muted-foreground">{prescription.computed_quantity ?? 'Quantity not set'} unit(s)</p></td>}{prescriptionColumns.dosage && <td className="text-xs">{prescription.dosage ?? '—'} · {prescription.frequency ?? '—'}</td>}{prescriptionColumns.status && <td><ClinicalStatusBadge status={prescription.status} /></td>}
                    <td><div className="flex min-w-[220px] justify-end gap-2"><ClinicalTableAction label={expandedPrescriptionId === prescription.id ? 'Hide details' : 'View order'} onClick={() => setExpandedPrescriptionId(expandedPrescriptionId === prescription.id ? null : prescription.id)} /><ClinicalTableAction label="Prepare" icon="acknowledge" onClick={() => void prepare(prescription)} /></div></td>
                      </tr>
                      {expandedPrescriptionId === prescription.id && (
                        <tr key={`${prescription.id}-details`} className="bg-muted/20">
                          <td colSpan={6}>
                            <div className="grid gap-3 md:grid-cols-[1fr_auto]">
                              <div><p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Dispensing details</p><p className="mt-2 text-sm">Select an available product or approved alternative, then confirm the quantity. Preparation does not reduce stock.</p><div className="mt-3 grid gap-2 sm:grid-cols-[1fr_120px]"><select value={matches[prescription.id] ?? ''} onChange={(event) => setMatches((current) => ({ ...current, [prescription.id]: event.target.value }))} className="input-medical"><option value="">Select product / supplier</option>{choices.map((item) => <option key={item.id} value={item.id}>{item.drug_name} · {item.supplier ?? 'In store'} · {item.stock_quantity} in stock</option>)}{inventory.filter((item) => item.stock_quantity > 0 && item.drug_name.toLowerCase().includes(prescription.medication.toLowerCase())).map((item) => <option key={item.id} value={item.id}>{item.drug_name} · {item.supplier ?? 'In store'} · {item.stock_quantity} in stock</option>)}</select><input type="number" min="1" value={quantities[prescription.id] ?? prescription.computed_quantity ?? 1} onChange={(event) => setQuantities((current) => ({ ...current, [prescription.id]: Number(event.target.value) }))} className="input-medical" aria-label={`Quantity for ${prescription.medication}`} /></div>{choices.length > 0 && <p className="mt-2 text-xs text-success">Approved alternatives are available by brand, supplier and current stock.</p>}</div>
                              <div className="flex items-end gap-2">{canCreateItems && inventory.filter((item) => item.drug_name.toLowerCase().includes(prescription.medication.toLowerCase())).length === 0 && <button type="button" onClick={() => setCreateMedicationName(prescription.medication)} className="btn-secondary text-xs">Add {prescription.medication}</button>}<button type="button" onClick={() => void prepare(prescription)} className="btn-primary text-xs">Prepare prescription</button></div>
                            </div>
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  );
                })}
                {plans.filter((plan) => appliedDispenseStatus === 'all' || appliedDispenseStatus === 'ready').map((plan) => (
                  <tr key={plan.id}>
                    <td>{plans.indexOf(plan) + 1}</td><td className="font-mono text-xs">{plan.patients?.patient_code ?? 'Prepared order'}</td><td><p className="font-semibold">{plan.patients ? `${plan.patients.first_name} ${plan.patients.last_name}` : 'Patient'}</p></td><td className="whitespace-nowrap text-xs text-muted-foreground">{plan.created_at ? new Date(plan.created_at).toLocaleString() : '—'}</td>
                    {prescriptionColumns.medication && <td><p className="font-medium">{plan.medication_name}</p><p className="text-xs text-muted-foreground">{plan.prepared_quantity} prepared</p></td>}{prescriptionColumns.dosage && <td className="text-xs">Prepared quantity: {plan.prepared_quantity}</td>}{prescriptionColumns.status && <td><ClinicalStatusBadge status={plan.service_order_status ?? 'pending'} /></td>}
                    <td><div className="flex justify-end"><ClinicalTableAction label="Dispense" icon="acknowledge" onClick={() => void dispense(plan)} disabled={!['released', 'in_progress'].includes(plan.service_order_status ?? '')} /></div></td>
                  </tr>
                ))}
              </tbody>
            </ClinicalDataTable>
            </>
          )}

          {tab === 'pos' && (
            <ClinicalDataTable
              title="Walk-in medication orders"
              description="Payment-gated POS medication orders with a clear release and dispensing action."
              meta={`${posSales.length} sale${posSales.length === 1 ? '' : 's'}`}
              filters={[{ label: 'Payment state', value: posStatusFilter, onChange: setPosStatusFilter, options: [{ value: 'all', label: 'All states' }, { value: 'pending', label: 'Awaiting release' }, { value: 'released', label: 'Released' }, { value: 'dispensed', label: 'Dispensed' }] }]}
              onSearch={() => setAppliedPosStatus(posStatusFilter)}
              loading={loading}
              empty={false}
            >
              <thead><tr><th scope="col">Medication</th><th scope="col">Quantity</th><th scope="col">Amount</th><th scope="col">Status</th><th scope="col">Workflow progress</th><th scope="col" className="text-right">Action</th></tr></thead>
              <tbody>{posSales.filter((sale) => appliedPosStatus === 'all' || sale.status === appliedPosStatus).map((sale) => (
                <tr key={sale.id}>
                  <td><p className="font-medium">{sale.medication}</p><p className="text-xs text-muted-foreground">POS medication order</p></td>
                  <td>{sale.quantity}</td>
                  <td>GHS {sale.total_amount.toFixed(2)}</td>
                  <td><ClinicalStatusBadge status={sale.status} /></td>
                  <td><ClinicalProgressBar value={sale.status === 'dispensed' ? 100 : ['released', 'in_progress'].includes(sale.status) ? 80 : 30} label="Order progress" /></td>
                  <td><div className="flex justify-end"><ClinicalTableAction label="View / dispense" onClick={() => setExpandedPosId(expandedPosId === sale.id ? null : sale.id)} disabled={!['released', 'in_progress'].includes(sale.status)} /></div></td>
                </tr>
              ))}</tbody>
            </ClinicalDataTable>
          )}

          {tab === 'inventory' && (
            <div>
              <div className="border-b border-border p-5">
                {canCreateItems && <form onSubmit={saveInventory} className="grid gap-3 md:grid-cols-2 lg:grid-cols-4">
                  {(['drug_name', 'brand_name', 'generic_name', 'strength', 'form', 'supplier', 'batch_number', 'expiry_date'] as const).map((field) => (
                    <div key={field}><label htmlFor={`inventory-${field}`} className="text-xs font-semibold block capitalize">{field.replace('_', ' ')}</label><input id={`inventory-${field}`} value={inventoryForm[field]} onChange={(event) => setInventoryForm((current) => ({ ...current, [field]: event.target.value }))} type={field === 'expiry_date' ? 'date' : 'text'} className="input-medical w-full mt-1" /></div>
                  ))}
                  <div><label htmlFor="inventory-stock" className="text-xs font-semibold block">Stock quantity</label><input id="inventory-stock" type="number" min="0" value={inventoryForm.stock_quantity} onChange={(event) => setInventoryForm((current) => ({ ...current, stock_quantity: Number(event.target.value) }))} className="input-medical w-full mt-1" /></div>
                  <div><label htmlFor="inventory-reorder" className="text-xs font-semibold block">Reorder level</label><input id="inventory-reorder" type="number" min="0" value={inventoryForm.reorder_level} onChange={(event) => setInventoryForm((current) => ({ ...current, reorder_level: Number(event.target.value) }))} className="input-medical w-full mt-1" /></div>
                  <div><label htmlFor="inventory-price" className="text-xs font-semibold block">Unit price</label><input id="inventory-price" type="number" min="0" step="0.01" value={inventoryForm.unit_price} onChange={(event) => setInventoryForm((current) => ({ ...current, unit_price: Number(event.target.value) }))} className="input-medical w-full mt-1" /></div>
                  <div className="md:col-span-2 lg:col-span-4 flex justify-end gap-2">{editingInventoryId && <button type="button" onClick={resetInventoryForm} className="btn-secondary">Cancel edit</button>}<button type="submit" className="btn-primary inline-flex items-center gap-2"><Package className="w-4 h-4" aria-hidden="true" /> {editingInventoryId ? 'Save changes' : 'Add to store'}</button></div>
                </form>}
              </div>}
              <ClinicalDataTable
                title="Pharmacy stock"
                description="Stock visibility remains medication-specific, with reorder risk and operational details rather than project-management fields."
                meta={`${visibleInventory.length} item${visibleInventory.length === 1 ? '' : 's'}`}
                filters={[
                  { label: 'Stock state', value: inventoryStockFilter, onChange: setInventoryStockFilter, options: [{ value: 'all', label: 'All stock' }, { value: 'available', label: 'In stock' }, { value: 'low', label: 'At / below reorder' }, { value: 'out', label: 'Out of stock' }] },
                ]}
                onSearch={() => setAppliedInventoryStock(inventoryStockFilter)}
                loading={loading}
                empty={false}
              >
                <thead><tr><th scope="col">Medication</th><th scope="col">Form / strength</th><th scope="col">Supplier / batch</th><th scope="col">Stock</th><th scope="col">Stock health</th><th scope="col">Expiry</th><th scope="col" className="text-right">Action</th></tr></thead>
                <tbody>{visibleInventory.filter((item) => appliedInventoryStock === 'all' || (appliedInventoryStock === 'available' && item.stock_quantity > item.reorder_level) || (appliedInventoryStock === 'low' && item.stock_quantity > 0 && item.stock_quantity <= item.reorder_level) || (appliedInventoryStock === 'out' && item.stock_quantity === 0)).map((item) => {
                  const stockProgress = item.reorder_level > 0 ? Math.min(100, Math.round((item.stock_quantity / (item.reorder_level * 3)) * 100)) : item.stock_quantity > 0 ? 100 : 0;
                  const low = item.stock_quantity <= item.reorder_level;
                  return (
                    <tr key={item.id} className={low ? 'bg-warning/5' : undefined}>
                      <td><p className="font-semibold">{item.drug_name}{item.brand_name ? ` · ${item.brand_name}` : ''}</p><p className="text-xs text-muted-foreground">{item.generic_name ?? 'Generic not recorded'}</p></td>
                      <td>{item.form ?? '—'} · {item.strength ?? 'Strength not recorded'}</td>
                      <td><p className="text-sm">{item.supplier ?? 'Supplier not recorded'}</p><p className="text-xs text-muted-foreground">{item.batch_number ?? 'Batch not recorded'}</p></td>
                      <td><p className="font-semibold">{item.stock_quantity}</p><p className="text-xs text-muted-foreground">reorder {item.reorder_level}</p></td>
                      <td><ClinicalProgressBar value={stockProgress} label={low ? 'Reorder' : 'Healthy'} /></td>
                      <td className="whitespace-nowrap text-xs">{item.expiry_date ?? 'No expiry recorded'}</td>
                      <td><div className="flex justify-end items-center gap-2">{canCreateItems && <button type="button" onClick={() => editInventoryItem(item)} className="btn-secondary inline-flex items-center gap-1.5 text-xs"><Pencil className="h-3.5 w-3.5" aria-hidden="true" /> Edit</button>}<ClinicalStatusBadge status={low ? 'pending' : 'approved'} label={low ? 'Review stock' : 'In stock'} /></div></td>
                    </tr>
                  );
                })}</tbody>
              </ClinicalDataTable>
            </div>
          )}
        </div>
      )}
      >
      </OperationalWorklistShell>
      {createMedicationName && <CatalogueCreateModal kind="pharmacy" initialName={createMedicationName} userRoles={user?.roles ?? []} userPermissions={user?.permissions ?? []} userDepartment={user?.department} onCreated={() => void load()} onClose={() => setCreateMedicationName('')} />}
    </>
  );
}
