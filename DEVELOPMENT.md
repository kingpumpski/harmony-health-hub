# Development Guide - Harmony Health Hub

## Quick Start

### Prerequisites
- Node.js 18+
- npm or bun
- Git

### Installation

```bash
# Clone repository
git clone https://github.com/kingpumpski/harmony-health-hub.git
cd harmony-health-hub

# Install dependencies
npm install
# or
bun install

# Create .env.local file with Supabase credentials
cp .env.example .env.local

# Start development server
npm run dev
# or
bun dev
```

Visit `http://localhost:5173` to view the application.

---

## Project Structure

```
src/
├── components/
│   ├── auth/                 # Authentication & RBAC
│   │   └── ProtectedRoute.tsx
│   ├── patients/             # Patient management
│   │   └── PatientRegistration.tsx
│   ├── records/              # Medical records
│   │   └── PatientMedicalRecords.tsx
│   ├── reports/              # Reporting & analytics
│   │   └── MonthlyReporting.tsx
│   ├── ui/                   # Reusable UI components (shadcn/ui)
│   └── layout/               # Layout components
├── constants/
│   └── medicalIcons.ts       # Medical icons & terminology
├── contexts/
│   └── AuthContext.tsx       # Authentication context
├── schemas/
│   └── medicalSchemas.ts     # Zod validation schemas
├── hooks/                    # Custom React hooks
├── pages/                    # Page components
├── App.tsx                   # Root component
└── main.tsx                  # Entry point
```

---

## Implementation Checklist

### Phase 1: Foundation ✅
- [x] Project setup and architecture
- [x] Medical icons and terminology system
- [x] Data validation schemas (Zod)
- [x] Authentication context with RBAC
- [x] Route protection components
- [x] Patient registration component
- [ ] Supabase backend setup
- [ ] User login/authentication flow
- [ ] Database migrations

### Phase 2: Core Features
- [ ] Patient management dashboard
- [ ] Medical records tracking
- [ ] Treatment cycle management (IVF, IUI, etc.)
- [ ] Laboratory module
- [ ] Medication tracking
- [ ] Appointment scheduling
- [ ] Clinical notes documentation

### Phase 3: Reporting & Analytics
- [ ] Monthly report generation
- [ ] Analytics dashboard
- [ ] Statistical analysis
- [ ] Automated report delivery
- [ ] Regulatory compliance reports
- [ ] Audit trail system

### Phase 4: Advanced Features
- [ ] Billing and payments
- [ ] Insurance claims processing
- [ ] Advanced notifications
- [ ] Data export (PDF, CSV)
- [ ] Mobile app
- [ ] API integrations

---

## Key Components

### 1. Medical Icons System
Located in `src/constants/medicalIcons.ts`

Provides:
- Medical icons for all fertility treatments
- Color-coded medical terms
- Navigation items with role-based access
- Helper functions for icons and medical terms

**Usage:**
```typescript
import { MedicalIcons, MedicalTerms, getIcon } from '@/constants/medicalIcons';

const icon = getIcon('ivf');
const term = MedicalTerms.IVF;
```

### 2. Data Validation Schemas
Located in `src/schemas/medicalSchemas.ts`

Provides:
- Zod schemas for all data entities
- Type-safe TypeScript interfaces
- Validation for forms and API responses

**Usage:**
```typescript
import { PatientSchema, CreatePatientSchema } from '@/schemas/medicalSchemas';

const validated = CreatePatientSchema.parse(formData);
```

### 3. Authentication Context
Located in `src/contexts/AuthContext.tsx`

Features:
- User authentication management
- Role-based access control (RBAC)
- Permission checking

**Usage:**
```typescript
import { useAuth } from '@/contexts/AuthContext';

export function MyComponent() {
  const { user, hasRole, canAccess } = useAuth();
  
  if (!hasRole('doctor')) {
    return <div>Access Denied</div>;
  }
  
  return <div>Doctor Content</div>;
}
```

### 4. Route Protection
Located in `src/components/auth/ProtectedRoute.tsx`

Components:
- `ProtectedRoute`: Wrapper for protected pages
- `RoleBased`: Conditional rendering based on roles

**Usage:**
```typescript
import { ProtectedRoute, RoleBased } from '@/components/auth/ProtectedRoute';

<ProtectedRoute requiredRoles={['doctor', 'admin']}>
  <DoctorDashboard />
</ProtectedRoute>

<RoleBased requiredRoles="admin">
  <AdminPanel />
</RoleBased>
```

---

## Database Schema

### Users Table
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  role TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

### Patients Table
```sql
CREATE TABLE patients (
  id UUID PRIMARY KEY,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  email TEXT,
  phone TEXT NOT NULL,
  date_of_birth DATE NOT NULL,
  gender TEXT NOT NULL,
  marital_status TEXT,
  address TEXT,
  city TEXT,
  state TEXT,
  postal_code TEXT,
  country TEXT,
  nationality TEXT,
  insurance_provider TEXT,
  insurance_policy_number TEXT,
  emergency_contact_name TEXT,
  emergency_contact_phone TEXT,
  emergency_contact_relation TEXT,
  medical_history_json JSONB,
  allergies TEXT[],
  medications TEXT[],
  status TEXT DEFAULT 'ACTIVE',
  registered_at TIMESTAMP,
  last_visit_at TIMESTAMP,
  discharged_at TIMESTAMP,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

### Treatments Table
```sql
CREATE TABLE treatments (
  id UUID PRIMARY KEY,
  patient_id UUID NOT NULL REFERENCES patients(id),
  spouse_patient_id UUID REFERENCES patients(id),
  type TEXT NOT NULL,
  protocol TEXT,
  start_date DATE NOT NULL,
  end_date DATE,
  status TEXT NOT NULL,
  current_phase TEXT,
  outcome TEXT,
  num_eggs_retrieved INTEGER,
  num_fertilized_eggs INTEGER,
  num_embryos_transferred INTEGER,
  embryo_grade TEXT,
  frozen_embryos_count INTEGER,
  notes TEXT,
  created_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

### Lab Tests Table
```sql
CREATE TABLE lab_tests (
  id UUID PRIMARY KEY,
  patient_id UUID NOT NULL REFERENCES patients(id),
  treatment_id UUID REFERENCES treatments(id),
  test_type TEXT NOT NULL,
  ordered_date DATE NOT NULL,
  ordered_by UUID NOT NULL REFERENCES users(id),
  completed_date DATE,
  completed_by UUID REFERENCES users(id),
  status TEXT NOT NULL,
  result_json JSONB,
  results_pdf TEXT,
  reference_range_json JSONB,
  interpretation TEXT,
  notes TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

---

## Styling Guidelines

### Color System
- **Blue**: Primary (IVF, consultations)
- **Purple**: Treatments (IUI, planning)
- **Pink**: Fertility-related (OI, ovulation)
- **Green**: Success (pregnancy, live birth)
- **Red**: Alerts (complications, failed cycles)
- **Amber/Orange**: Caution (OHSS, pending results)
- **Teal**: Genetics (PGD, genetic testing)

### Icons Usage
- Use medical-specific icons from Lucide React
- Pair icons with labels for clarity
- Maintain consistent sizing (h-4, h-5, h-6, h-8)
- Use appropriate colors that match medical meaning

---

## API Integration (TODO)

### Supabase Setup

1. Create Supabase project
2. Run migrations from `supabase/migrations/`
3. Set up Row-Level Security (RLS) policies
4. Configure authentication

### Environment Variables

```env
VITE_SUPABASE_URL=your_supabase_url
VITE_SUPABASE_ANON_KEY=your_anon_key
VITE_API_BASE_URL=http://localhost:3000
```

---

## Testing

### Setup

```bash
npm install -D vitest @testing-library/react @testing-library/jest-dom
```

### Running Tests

```bash
npm run test           # Run tests
npm run test:watch    # Watch mode
npm run test:coverage # Coverage report
```

### Example Test

```typescript
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { PatientRegistration } from '@/components/patients/PatientRegistration';

describe('PatientRegistration', () => {
  it('renders registration form', () => {
    render(<PatientRegistration />);
    expect(screen.getByText(/register new patient/i)).toBeInTheDocument();
  });
});
```

---

## Code Quality

### ESLint

```bash
npm run lint          # Check for issues
npm run lint:fix      # Auto-fix issues
```

### Prettier

```bash
# Format code
npx prettier --write src/
```

### Pre-commit Hooks (Husky + lint-staged)

```bash
npm install -D husky lint-staged

# Setup
npx husky install
npx husky add .husky/pre-commit "npx lint-staged"
```

Configure `.lintstagedrc.json`:
```json
{
  "*.{ts,tsx}": "eslint --fix",
  "*.{ts,tsx,css,md}": "prettier --write"
}
```

---

## Deployment

### Vercel (Frontend)

```bash
npm run build
# Push to GitHub, Vercel auto-deploys
```

### Supabase (Backend)

- Managed PostgreSQL database
- Automatic backups
- Real-time synchronization

---

## Common Tasks

### Adding a New Medical Term

1. Add to `MedicalTerms` in `src/constants/medicalIcons.ts`
2. Map to appropriate icon
3. Assign color
4. Update related schemas if needed

### Adding a New Feature

1. Create schema in `src/schemas/medicalSchemas.ts`
2. Create component in appropriate folder under `src/components/`
3. Add navigation item if needed
4. Protect routes with RBAC

### Adding a New Page

1. Create page component in `src/pages/`
2. Add route in routing configuration
3. Protect with `ProtectedRoute` if needed
4. Add navigation link in sidebar

---

## Troubleshooting

### Port Already in Use
```bash
# Change port
npm run dev -- --port 3000
```

### Node Modules Issues
```bash
rm -rf node_modules package-lock.json
npm install
```

### TypeScript Errors
```bash
# Clear cache
rm -rf dist .turbo
npm run build
```

---

## Resources

- [React Documentation](https://react.dev)
- [TypeScript Handbook](https://www.typescriptlang.org/docs/)
- [Tailwind CSS](https://tailwindcss.com/docs)
- [shadcn/ui](https://ui.shadcn.com/)
- [Zod Documentation](https://zod.dev)
- [Supabase Docs](https://supabase.com/docs)
- [Lucide React Icons](https://lucide.dev)

---

## Contributing

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Commit changes: `git commit -m "feat: add your feature"`
3. Push to branch: `git push origin feature/your-feature`
4. Submit pull request

---

## License

MIT License - See LICENSE file for details

---

## Support

For issues and questions:
- GitHub Issues: [Create an issue](https://github.com/kingpumpski/harmony-health-hub/issues)
- Email: support@harmonyhealth.clinic

---

**Last Updated:** April 2024
**Version:** 1.0.0
