import { Link } from 'react-router-dom';
import { CreditCard, FileCheck2, Receipt, ShieldCheck } from 'lucide-react';

const items = [
  { label: 'Billing & Invoices', href: '/billing', icon: CreditCard, description: 'Patient billing, invoices and account balances.' },
  { label: 'Accounts Approvals', href: '/accounts-approvals', icon: FileCheck2, description: 'Approve pending clinical services and financial releases.' },
  { label: 'Insurance Claims', href: '/insurance-claims', icon: ShieldCheck, description: 'Manage insurer claims and response workflows.' },
  { label: 'Tariff Adjustments', href: '/billing/tariffs', icon: Receipt, description: 'Controlled tariff review and authorized adjustments.' },
  { label: 'Financial Reports', href: '/financial-reports', icon: Receipt, description: 'Financial settlement and reconciliation reporting.' },
];

export default function FinanceWorkspace() {
  return <div className="space-y-6 animate-fade-in"><header><div className="flex items-center gap-3"><CreditCard className="h-7 w-7 text-primary" /><div><div className="mb-2 text-[10px] font-semibold uppercase tracking-[0.16em] text-primary">Business · Finance</div><h1 className="text-2xl font-heading font-bold">Finance</h1><p className="text-sm text-muted-foreground">The financial lifecycle around patient care, billing, approvals, insurance and reconciliation.</p></div></div></header><div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">{items.map(item => { const Icon=item.icon; return <Link key={item.href} to={item.href} className="card-medical p-5 transition-transform hover:-translate-y-0.5"><Icon className="h-5 w-5 text-primary" /><h2 className="mt-4 font-semibold">{item.label}</h2><p className="mt-1 text-sm text-muted-foreground">{item.description}</p></Link>; })}</div></div>;
}
