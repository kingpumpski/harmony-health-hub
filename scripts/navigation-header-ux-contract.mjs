import fs from 'node:fs';

const read = (p) => fs.readFileSync(p, 'utf8');
const sidebar = read('src/components/layout/Sidebar.tsx');
const header = read('src/components/layout/Header.tsx');
const search = read('src/lib/globalWorkspaceSearch.ts');
const app = read('src/App.tsx');
const failures = [];
const check = (name, condition) => { if (!condition) failures.push(name); };

check('Healthcare is the canonical clinical workspace label', sidebar.includes("'Healthcare'") && !sidebar.includes("'Clinical Operations'"));
check('Healthcare appears in global workspace search', search.includes("title:'Healthcare'") && !search.includes("title:'Clinical Operations'"));
check('normal users do not get a facility switcher in the header', !header.includes('get_user_facilities') && !header.includes('set_active_facility_context') && !header.includes('Active facility'));
check('facility sharing administration is routed', app.includes('/admin/facility-sharing') && app.includes('FacilityDataSharing'));
check('platform user management includes System Superuser', app.includes("path=\"/admin/users\"") && app.includes('system_superuser'));
check('facility attribution administration is routed', app.includes('/admin/facility-attribution') && app.includes('FacilityAttributionReview'));


const layout = read('src/components/layout/MainLayout.tsx');
const routeLoading = read('src/components/system/RouteLoadingScreen.tsx');
check('authenticated layout provides a keyboard skip link and focusable main landmark', layout.includes('Skip to main content') && layout.includes('id="main-content" tabIndex={-1}'));
check('route-aware loading status is announced accessibly and motion respects reduced-motion preferences', routeLoading.includes('aria-live="polite"') && routeLoading.includes('motion-reduce:animate-none') && routeLoading.includes('Loading {moduleName}'));
check('mobile navigation closes when the route changes', layout.includes('setMobileNavOpen(false);') && layout.includes('[location.pathname]'));

if (failures.length) {
  console.error('Navigation/header UX contract failures:');
  failures.forEach((failure) => console.error('- ' + failure));
  process.exitCode = 1;
} else {
  console.log('Navigation/header UX contract passed.');
}
