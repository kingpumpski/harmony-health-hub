import AccountsApprovals from '@/pages/AccountsApprovals';

/**
 * Accounts dashboard compatibility surface.
 *
 * The operational Accounts workflow is owned by AccountsApprovals so the
 * dashboard and /accounts-approvals route cannot drift into separate billing
 * implementations. Keep this component as the role-dashboard entry point.
 */
export default function AccountsDashboard() {
  return <AccountsApprovals />;
}
