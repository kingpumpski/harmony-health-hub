import { useCallback, useEffect, useMemo, useState } from 'react';
import { Archive, CalendarClock, Calculator, Pencil, Plus, RefreshCw, UserRound } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from '@/components/ui/dialog';

type Period = {
  id: string;
  name: string;
  period_start: string;
  period_end: string;
  pay_date: string;
  status: string;
};

type PayrollEmployee = { first_name: string; last_name: string; employee_number: string };
type Item = {
  id: string;
  employee_id: string;
  basic_pay: number;
  allowances: number;
  other_earnings: number;
  statutory_deductions: number;
  other_deductions: number;
  gross_pay: number;
  net_pay: number;
  status: string;
  payment_reference: string | null;
  employee?: PayrollEmployee;
};

type PeriodDraft = { name: string; period_start: string; period_end: string; pay_date: string };
type ItemDraft = {
  basic_pay: string;
  allowances: string;
  other_earnings: string;
  statutory_deductions: string;
  other_deductions: string;
  payment_reference: string;
};

const db = supabase as any;
const itemFields = 'id,employee_id,basic_pay,allowances,other_earnings,statutory_deductions,other_deductions,gross_pay,net_pay,status,payment_reference,hr_employees(first_name,last_name,employee_number)';
const emptyPeriodDraft = (): PeriodDraft => ({ name: '', period_start: '', period_end: '', pay_date: '' });
const emptyItemDraft = (): ItemDraft => ({
  basic_pay: '0', allowances: '0', other_earnings: '0',
  statutory_deductions: '0', other_deductions: '0', payment_reference: '',
});
const currency = (value: number) => `GHS ${Number(value || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

async function activeFacilityId() {
  const { data, error } = await db.rpc('current_user_facility_id');
  if (error || !data) throw new Error(error?.message || 'No active facility is selected.');
  return data as string;
}

export default function Payroll() {
  const { user } = useAuth();
  const [periods, setPeriods] = useState<Period[]>([]);
  const [selected, setSelected] = useState<Period | null>(null);
  const [items, setItems] = useState<Item[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [generating, setGenerating] = useState(false);
  const [periodEditorOpen, setPeriodEditorOpen] = useState(false);
  const [itemEditorOpen, setItemEditorOpen] = useState(false);
  const [editingPeriod, setEditingPeriod] = useState<Period | null>(null);
  const [editingItem, setEditingItem] = useState<Item | null>(null);
  const [cancelTarget, setCancelTarget] = useState<Period | null>(null);
  const [voidTarget, setVoidTarget] = useState<Item | null>(null);
  const [periodDraft, setPeriodDraft] = useState<PeriodDraft>(emptyPeriodDraft);
  const [itemDraft, setItemDraft] = useState<ItemDraft>(emptyItemDraft);

  const canManage = ['admin', 'it_admin', 'accountant'].includes(user?.role ?? '');

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await db.from('payroll_periods')
      .select('id,name,period_start,period_end,pay_date,status')
      .order('period_start', { ascending: false });
    if (error) {
      toast.error(`Unable to load payroll periods: ${error.message}`);
    } else {
      const nextPeriods = (data ?? []) as Period[];
      setPeriods(nextPeriods);
      setSelected((current) => current ? nextPeriods.find((period) => period.id === current.id) ?? null : null);
    }
    setLoading(false);
  }, []);

  const loadItems = useCallback(async (period: Period) => {
    const { data, error } = await db.from('payroll_items')
      .select(itemFields)
      .eq('payroll_period_id', period.id)
      .order('created_at');
    if (error) {
      toast.error(`Unable to load payroll items: ${error.message}`);
      return;
    }
    setItems((data ?? []).map((row: any) => ({ ...row, employee: row.hr_employees })) as Item[]);
  }, []);

  useEffect(() => { void load(); }, [load]);

  const selectPeriod = async (period: Period) => {
    setSelected(period);
    setItems([]);
    await loadItems(period);
  };

  const openNewPeriod = () => {
    setEditingPeriod(null);
    setPeriodDraft(emptyPeriodDraft());
    setPeriodEditorOpen(true);
  };

  const openEditPeriod = (period: Period) => {
    setEditingPeriod(period);
    setPeriodDraft({
      name: period.name,
      period_start: period.period_start,
      period_end: period.period_end,
      pay_date: period.pay_date,
    });
    setPeriodEditorOpen(true);
  };

  const savePeriod = async () => {
    if (!canManage) return;
    if (!periodDraft.name.trim() || !periodDraft.period_start || !periodDraft.period_end || !periodDraft.pay_date) {
      toast.error('Period name, start date, end date and pay date are required.');
      return;
    }
    if (periodDraft.period_end < periodDraft.period_start) {
      toast.error('The period end date must be on or after its start date.');
      return;
    }
    setSaving(true);
    try {
      const payload = {
        ...periodDraft,
        name: periodDraft.name.trim(),
        updated_at: new Date().toISOString(),
      };
      const query = editingPeriod
        ? db.from('payroll_periods').update(payload).eq('id', editingPeriod.id)
        : db.from('payroll_periods').insert({
          ...payload,
          facility_id: await activeFacilityId(),
          created_by: user?.id,
        });
      const { error } = await query;
      if (error) throw new Error(error.message);
      toast.success(editingPeriod ? 'Payroll period updated.' : 'Payroll period created.');
      setPeriodEditorOpen(false);
      await load();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Unable to save payroll period.');
    } finally {
      setSaving(false);
    }
  };

  const generate = async () => {
    if (!selected || selected.status !== 'draft' || !canManage) return;
    setGenerating(true);
    try {
      const { data, error } = await db.rpc('generate_payroll_items', { _payroll_period_id: selected.id });
      if (error) throw new Error(error.message);
      toast.success(`${Number(data ?? 0)} payroll item${Number(data ?? 0) === 1 ? '' : 's'} generated from active employees.`);
      await loadItems(selected);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Unable to generate payroll items.');
    } finally {
      setGenerating(false);
    }
  };

  const cancelPeriod = async (period: Period) => {
    if (!canManage || period.status !== 'draft') return;
    const { error } = await db.from('payroll_periods')
      .update({ status: 'cancelled', updated_at: new Date().toISOString() })
      .eq('id', period.id);
    if (error) {
      toast.error(`Unable to cancel payroll period: ${error.message}`);
      return;
    }
    toast.success('Payroll period cancelled. Its payroll history has been retained.');
    setCancelTarget(null);
    await load();
  };

  const openEditItem = (item: Item) => {
    setEditingItem(item);
    setItemDraft({
      basic_pay: String(item.basic_pay),
      allowances: String(item.allowances),
      other_earnings: String(item.other_earnings),
      statutory_deductions: String(item.statutory_deductions),
      other_deductions: String(item.other_deductions),
      payment_reference: item.payment_reference ?? '',
    });
    setItemEditorOpen(true);
  };

  const saveItem = async () => {
    if (!canManage || !editingItem || selected?.status !== 'draft') return;
    const amounts = {
      basic_pay: Number(itemDraft.basic_pay),
      allowances: Number(itemDraft.allowances),
      other_earnings: Number(itemDraft.other_earnings),
      statutory_deductions: Number(itemDraft.statutory_deductions),
      other_deductions: Number(itemDraft.other_deductions),
    };
    if (Object.values(amounts).some((amount) => !Number.isFinite(amount) || amount < 0)) {
      toast.error('All pay amounts must be valid non-negative numbers.');
      return;
    }
    const grossPay = amounts.basic_pay + amounts.allowances + amounts.other_earnings;
    const netPay = Math.max(0, grossPay - amounts.statutory_deductions - amounts.other_deductions);
    setSaving(true);
    const { error } = await db.from('payroll_items').update({
      ...amounts,
      gross_pay: grossPay,
      net_pay: netPay,
      payment_reference: itemDraft.payment_reference.trim() || null,
      updated_at: new Date().toISOString(),
    }).eq('id', editingItem.id);
    setSaving(false);
    if (error) {
      toast.error(`Unable to update payroll item: ${error.message}`);
      return;
    }
    toast.success('Payroll item updated and totals recalculated.');
    setItemEditorOpen(false);
    await loadItems(selected);
  };

  const voidItem = async (item: Item) => {
    if (!canManage || selected?.status !== 'draft' || item.status !== 'draft') return;
    const { error } = await db.from('payroll_items')
      .update({ status: 'void', updated_at: new Date().toISOString() })
      .eq('id', item.id);
    if (error) {
      toast.error(`Unable to void payroll item: ${error.message}`);
      return;
    }
    toast.success('Payroll item voided. Its pay values remain available for audit.');
    setVoidTarget(null);
    await loadItems(selected);
  };

  const totals = useMemo(() => items.reduce((sum, item) => ({
    gross: sum.gross + (item.status === 'void' ? 0 : Number(item.gross_pay)),
    net: sum.net + (item.status === 'void' ? 0 : Number(item.net_pay)),
  }), { gross: 0, net: 0 }), [items]);

  const periodField = (key: keyof PeriodDraft, label: string, type: string) => (
    <label key={key} className="space-y-1 text-sm">
      <span className="font-medium">{label}</span>
      <input className="input-medical w-full" type={type} value={periodDraft[key]} onChange={(event) => setPeriodDraft((current) => ({ ...current, [key]: event.target.value }))} />
    </label>
  );

  const amountField = (key: Exclude<keyof ItemDraft, 'payment_reference'>, label: string) => (
    <label key={key} className="space-y-1 text-sm">
      <span className="font-medium">{label}</span>
      <input className="input-medical w-full" type="number" min="0" step="0.01" value={itemDraft[key]} onChange={(event) => setItemDraft((current) => ({ ...current, [key]: event.target.value }))} />
    </label>
  );

  return (
    <div className="space-y-6 animate-fade-in">
      <header className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-heading font-bold"><CalendarClock className="h-6 w-6 text-primary" />Payroll</h1>
          <p className="text-sm text-muted-foreground">Manage draft payroll periods and auditable employee pay calculations.</p>
        </div>
        <div className="flex gap-2">
          <button type="button" className="btn-secondary h-10 w-10 p-0" aria-label="Refresh payroll" onClick={() => void load()}><RefreshCw className="h-4 w-4" /></button>
          {canManage && <button type="button" className="btn-primary inline-flex gap-2" onClick={openNewPeriod}><Plus className="h-4 w-4" />New period</button>}
        </div>
      </header>

      <div className="grid gap-5 lg:grid-cols-[22rem_minmax(0,1fr)]">
        <section className="card-medical overflow-hidden">
          <div className="flex items-center justify-between border-b p-4"><div><h2 className="font-semibold">Payroll periods</h2><p className="text-xs text-muted-foreground">{periods.length} record{periods.length === 1 ? '' : 's'}</p></div><button type="button" className="btn-secondary h-9 w-9 p-0" aria-label="Refresh periods" onClick={() => void load()}><RefreshCw className="h-4 w-4" /></button></div>
          <div className="divide-y">
            {loading && <p className="p-6 text-sm text-muted-foreground">Loading payroll periods…</p>}
            {!loading && periods.map((period) => (
              <div key={period.id} className={`p-4 ${selected?.id === period.id ? 'bg-muted/50' : ''}`}>
                <button type="button" onClick={() => void selectPeriod(period)} className="block w-full text-left">
                  <div className="font-medium">{period.name}</div>
                  <div className="mt-1 text-xs text-muted-foreground">{period.period_start} → {period.period_end}<br />Pay date: {period.pay_date}</div>
                  <span className={`${period.status === 'draft' ? 'badge-warning' : period.status === 'paid' ? 'badge-success' : 'badge-info'} mt-2 inline-flex`}>{period.status}</span>
                </button>
                {canManage && period.status === 'draft' && <div className="mt-3 flex gap-2">
                  <button type="button" className="btn-secondary h-8 px-2 text-xs" onClick={() => openEditPeriod(period)}><Pencil className="h-3.5 w-3.5" />Edit</button>
                  <button type="button" className="btn-secondary h-8 px-2 text-xs" onClick={() => setCancelTarget(period)}><Archive className="h-3.5 w-3.5" />Cancel period</button>
                </div>}
              </div>
            ))}
            {!loading && periods.length === 0 && <p className="p-6 text-sm text-muted-foreground">No payroll periods yet. Create a period to begin a payroll run.</p>}
          </div>
        </section>

        <section className="card-medical overflow-hidden">
          <div className="flex flex-col gap-4 border-b p-4 xl:flex-row xl:items-center xl:justify-between">
            <div>
              <h2 className="font-semibold">{selected?.name ?? 'Payroll run'}</h2>
              <p className="text-xs text-muted-foreground">{items.length} employee line{items.length === 1 ? '' : 's'} · {currency(totals.gross)} gross · {currency(totals.net)} net</p>
            </div>
            {selected && canManage && selected.status === 'draft' && <button type="button" className="btn-primary inline-flex gap-2" disabled={generating} onClick={() => void generate()}><Calculator className="h-4 w-4" />{generating ? 'Generating…' : 'Generate from active employees'}</button>}
          </div>
          <div className="overflow-x-auto">
            <table className="table-medical w-full">
              <thead><tr><th>Employee</th><th>Basic</th><th>Earnings</th><th>Deductions</th><th>Gross</th><th>Net</th><th>Status</th>{canManage && <th className="text-right">Actions</th>}</tr></thead>
              <tbody>
                {items.map((item) => (
                  <tr key={item.id} className={item.status === 'void' ? 'opacity-60' : ''}>
                    <td><div className="flex items-center gap-2 font-medium"><UserRound className="h-4 w-4 text-muted-foreground" />{item.employee?.first_name} {item.employee?.last_name}</div><div className="pl-6 text-xs text-muted-foreground">{item.employee?.employee_number}</div></td>
                    <td>{currency(item.basic_pay)}</td>
                    <td>{currency(Number(item.allowances) + Number(item.other_earnings))}</td>
                    <td>{currency(Number(item.statutory_deductions) + Number(item.other_deductions))}</td>
                    <td>{currency(item.gross_pay)}</td>
                    <td className="font-semibold">{currency(item.net_pay)}</td>
                    <td><span className={item.status === 'void' ? 'badge-info' : item.status === 'paid' ? 'badge-success' : item.status === 'draft' ? 'badge-warning' : 'badge-info'}>{item.status}</span></td>
                    {canManage && <td><div className="flex justify-end gap-2">
                      {selected?.status === 'draft' && item.status === 'draft' && <>
                        <button type="button" className="btn-secondary h-8 w-8 p-0" aria-label="Edit payroll item" onClick={() => openEditItem(item)}><Pencil className="h-4 w-4" /></button>
                        <button type="button" className="btn-secondary h-8 w-8 p-0" aria-label="Void payroll item" onClick={() => setVoidTarget(item)}><Archive className="h-4 w-4" /></button>
                      </>}
                    </div></td>}
                  </tr>
                ))}
                {!items.length && <tr><td colSpan={canManage ? 8 : 7} className="p-10 text-center text-sm text-muted-foreground">{selected ? 'No employee lines yet. Generate items from active employees to start this draft run.' : 'Select a payroll period to review its employee lines.'}</td></tr>}
              </tbody>
            </table>
          </div>
          {selected && selected.status !== 'draft' && <p className="border-t bg-muted/30 p-4 text-sm text-muted-foreground">This period is {selected.status}. Pay values are read-only and retained for payroll audit history.</p>}
        </section>
      </div>

      <Dialog open={periodEditorOpen} onOpenChange={setPeriodEditorOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>{editingPeriod ? 'Edit payroll period' : 'Create payroll period'}</DialogTitle><DialogDescription>Payroll periods can only be edited while in draft. Cancelled periods are retained for audit.</DialogDescription></DialogHeader>
          <div className="grid gap-4 sm:grid-cols-2">
            {periodField('name', 'Period name', 'text')}
            {periodField('period_start', 'Start date', 'date')}
            {periodField('period_end', 'End date', 'date')}
            {periodField('pay_date', 'Pay date', 'date')}
          </div>
          <DialogFooter><button type="button" className="btn-secondary" onClick={() => setPeriodEditorOpen(false)}>Close</button><button type="button" className="btn-primary" disabled={saving} onClick={() => void savePeriod()}>{saving ? 'Saving…' : editingPeriod ? 'Save changes' : 'Create period'}</button></DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog open={itemEditorOpen} onOpenChange={setItemEditorOpen}>
        <DialogContent className="max-h-[90vh] overflow-y-auto">
          <DialogHeader><DialogTitle>Edit payroll item</DialogTitle><DialogDescription>Totals are recalculated from earnings and deductions. The database validates every amount and locks finalized records.</DialogDescription></DialogHeader>
          {editingItem && <div className="rounded-lg bg-muted/40 p-3 text-sm font-medium">{editingItem.employee?.first_name} {editingItem.employee?.last_name} · {editingItem.employee?.employee_number}</div>}
          <div className="grid gap-4 sm:grid-cols-2">
            {amountField('basic_pay', 'Basic pay (GHS)')}
            {amountField('allowances', 'Allowances (GHS)')}
            {amountField('other_earnings', 'Other earnings (GHS)')}
            {amountField('statutory_deductions', 'Statutory deductions (GHS)')}
            {amountField('other_deductions', 'Other deductions (GHS)')}
            <label className="space-y-1 text-sm"><span className="font-medium">Payment reference</span><input className="input-medical w-full" value={itemDraft.payment_reference} onChange={(event) => setItemDraft((current) => ({ ...current, payment_reference: event.target.value }))} /></label>
          </div>
          <DialogFooter><button type="button" className="btn-secondary" onClick={() => setItemEditorOpen(false)}>Cancel</button><button type="button" className="btn-primary" disabled={saving} onClick={() => void saveItem()}>{saving ? 'Saving…' : 'Save payroll item'}</button></DialogFooter>
        </DialogContent>
      </Dialog>

      <AlertDialog open={Boolean(cancelTarget)} onOpenChange={(open) => { if (!open) setCancelTarget(null); }}>
        <AlertDialogContent><AlertDialogHeader><AlertDialogTitle>Cancel this payroll period?</AlertDialogTitle><AlertDialogDescription>The period and its payroll lines will be retained, but the period can no longer be edited or used to generate payroll items.</AlertDialogDescription></AlertDialogHeader>
          <AlertDialogFooter><AlertDialogCancel>Keep period</AlertDialogCancel><AlertDialogAction onClick={(event) => { event.preventDefault(); if (cancelTarget) void cancelPeriod(cancelTarget); }}>Cancel period</AlertDialogAction></AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={Boolean(voidTarget)} onOpenChange={(open) => { if (!open) setVoidTarget(null); }}>
        <AlertDialogContent><AlertDialogHeader><AlertDialogTitle>Void this payroll item?</AlertDialogTitle><AlertDialogDescription>The line will be excluded from totals and future processing. Its original pay values remain in the audit record.</AlertDialogDescription></AlertDialogHeader>
          <AlertDialogFooter><AlertDialogCancel>Keep item</AlertDialogCancel><AlertDialogAction onClick={(event) => { event.preventDefault(); if (voidTarget) void voidItem(voidTarget); }}>Void item</AlertDialogAction></AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
