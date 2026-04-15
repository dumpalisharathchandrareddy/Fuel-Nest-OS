# FuelOS — Fuel Station Management System

> Flutter app for Indian fuel stations. Android · iOS · Windows · macOS.  
> Direct Supabase — no Express server. On-device PDF/Excel. Discord alerts. Google Drive backup.

---

## Quick Start (5 minutes to first run)

### 1. Generate platform boilerplate
```bash
# In your project root (where pubspec.yaml is)
flutter create --project-name fuelos --org com.fuelos --platforms android,ios,windows,macos .
# Flutter skips files that already exist — your lib/ code is safe
```

### 2. Set your registry Supabase credentials
Edit `lib/core/constants/app_constants.dart`:
```dart
static const registrySupabaseUrl = 'https://YOUR_REGISTRY_PROJECT.supabase.co';
static const registryAnonKey     = 'YOUR_REGISTRY_ANON_KEY';
```
> This is **your own** Supabase project — the central lookup table (not each dealer's).

### 3. Install dependencies
```bash
flutter pub get
```

### 4. Deploy edge functions
```bash
npm install -g supabase    # one-time
supabase login

# Link to each dealer's Supabase project:
supabase link --project-ref YOUR_DEALER_PROJECT_REF

# Set the internal salt secret (any random string, keep it private):
supabase secrets set INTERNAL_SALT="your_very_secret_random_salt_here"

# Deploy all 4 edge functions:
supabase functions deploy auth-login
supabase functions deploy auth-signup-dealer
supabase functions deploy create-staff
supabase functions deploy set-user-pin
```

### 5. Run database migrations on each dealer's Supabase
In **Supabase Dashboard → SQL Editor**, run in order:
1. Your existing Prisma schema SQL (from `backend/prisma/...`)
2. `supabase/migrations/001_enable_rls.sql`
3. `supabase/migrations/002_rls_policies.sql`

### 6. Set up central registry
In **your registry Supabase** SQL Editor:
```sql
-- Run: registry_supabase/registry_schema.sql
```

### 7. Run
```bash
flutter run -d android    # Android (APK sideload)
flutter run -d windows    # Windows desktop
flutter run -d macos      # macOS desktop
flutter run -d ios        # iOS (requires Xcode + Apple dev account)
```

---

## Architecture

```
FuelOS App (Flutter)
│
├── Central Registry (your Supabase)
│   └── station_registry: station_code → dealer's Supabase URL + anon key
│
└── Per-Dealer Supabase (each dealer's own project)
    ├── PostgreSQL DB (your existing Prisma schema)
    ├── Edge Functions (auth-login, auth-signup-dealer, create-staff, set-user-pin)
    └── Row Level Security (enforced via JWT claims)
```

**Data flow:**
1. User enters Station Code → app looks up in central registry → gets dealer's Supabase URL
2. User logs in → Edge Function validates credentials → returns Supabase Auth JWT
3. All subsequent queries go directly to dealer's Supabase with JWT (RLS enforced)

---

## 4 Hubs

| Hub | Who | What they enter | What they see |
|-----|-----|-----------------|---------------|
| **Dealer** | Owner | Station Code + Password | Everything — settings, payroll, all reports |
| **Manager** | Station manager | Station Code + Username + PIN/Password | Operations — shifts, inventory, payroll |
| **Staff** | Pump operator | Station Code + Employee ID + PIN | Their shifts only — nozzle readings, earnings |
| **Creditor** | Credit customer | Station Code + Mobile Number | Their balance + transaction history |

---

## Edge Functions

| Function | Purpose | Who calls it |
|----------|---------|--------------|
| `auth-login` | Validates username/PIN/password, returns JWT session | All 3 staff roles |
| `auth-signup-dealer` | Creates station + owner account, registers in central registry | New dealers only |
| `create-staff` | Creates staff member with bcrypt-hashed password + salary config | Manager/Dealer |
| `set-user-pin` | Hashes and saves 4–6 digit PIN for a staff member | Manager/Dealer |

---

## Google Sign-In Setup (for Google Drive backup)

### Android
1. Create a project at [console.cloud.google.com](https://console.cloud.google.com)
2. Enable **Google Drive API**
3. Create OAuth 2.0 credentials → Android → add your app's SHA-1
4. Download `google-services.json` → place in `android/app/`

### iOS
1. Same Google Cloud project
2. Create OAuth 2.0 credentials → iOS → bundle ID `com.fuelos.app`
3. Download `GoogleService-Info.plist` → place in `ios/Runner/`
4. Copy the `REVERSED_CLIENT_ID` from the plist → add to `ios/Runner/Info.plist` URL scheme

### macOS
Same as iOS credentials, add to `macos/Runner/GoogleService-Info.plist`.

---

## Export Formats

| Screen | PDF | CSV | WhatsApp |
|--------|-----|-----|----------|
| Shifts | ✅ Full report | ✅ | ✅ Summary |
| Payroll | ✅ Pay slips | — | — |
| Inventory | ✅ Tank + orders | — | ✅ Tank levels |
| Credit | — | — | ✅ Per-customer reminder |
| Reports | ✅ All types | ✅ | ✅ |
| Expenses | — | — | ✅ Summary |

---

## Database Notes

### Existing schema compatibility
FuelOS uses your **existing Prisma schema tables unchanged**.

Only 2 new columns are added by migration `002`:
- `User.supabase_auth_id` — links your User to Supabase Auth
- `User.pin_hash` — stores bcrypt-hashed PIN for PIN-based login

### Password compatibility
Existing `password_hash` values from your Node.js/bcrypt setup work directly. The Edge Function uses Deno's bcrypt which is compatible.

### RLS helpers (created by migration 002)
```sql
fuelos_station_id()  -- returns station_id from JWT metadata
fuelos_role()        -- returns role from JWT metadata  
fuelos_user_id()     -- returns app user ID from JWT metadata
```

---

## Supabase RLS Summary

| Table | Who can read | Who can write |
|-------|-------------|---------------|
| Shift, NozzleEntry | Same station (all roles) | Same station |
| PaymentRecord, FuelRate | Same station | Manager + Dealer |
| CreditCustomer, CreditTransaction | Same station | Manager + Dealer |
| SalaryConfig, SalaryPayout | Manager+Dealer (own for staff) | Manager + Dealer |
| Tank, Pump, Nozzle | Same station | Manager + Dealer |
| FuelOrder, InventoryCheque | Same station | Same station |
| User | Same station | Manager + Dealer |
| AuditLog | Manager + Dealer | Same station |

---

## India-Specific

- **Currency:** ₹ with Indian number format (1,23,456 not 1,234,567)
- **Compact:** ₹1.2L (lakhs), ₹3.4Cr (crores) for dashboards
- **Timezone:** All UI in IST (Asia/Kolkata, UTC+5:30). All DB in UTC.
- **Phone format:** 10-digit Indian mobile numbers
- **Distribution:** APK sideload (no Play Store needed) · Windows installer · macOS .app

---

## Development

```bash
# Run with hot reload
flutter run

# Build release APK
flutter build apk --release --split-per-abi

# Build Windows installer
flutter build windows --release

# Run tests
flutter test

# Analyze code
flutter analyze
```

---

## File Structure

```
lib/
├── main.dart                    App entry, timezone + Supabase init
├── app.dart                     GoRouter with all routes
├── core/
│   ├── constants/               AppColors, AppConstants (fuel types, roles)
│   ├── models/                  AuthUser, Shift, Tank, NozzleEntry, etc.
│   ├── providers/               Riverpod: AuthState, AuthNotifier
│   ├── services/                Supabase, Discord, Drive, Export, Auth
│   └── utils/                   IstTime (IST clock), IndianCurrency, Validators
├── shared/
│   ├── layout/main_shell.dart   Adaptive nav: Desktop sidebar / Tablet rail / Mobile bottom
│   ├── theme/app_theme.dart     Full dark Material 3 theme matching web CSS
│   └── widgets/widgets.dart     AppButton, AppCard, AppTextField, StatusBadge, KpiCard...
└── features/
    ├── auth/                    Splash, StationCode, RoleSelect, Login, DealerSignup
    ├── dashboard/               Manager KPI dashboard
    ├── shifts/                  ShiftList (launch + date filter) + PaymentReconciliation
    ├── inventory/               TankDashboard + FuelOrder + ChequeEntry + DipReading
    ├── credit/                  CreditManagement (ledger, add entry, record payment)
    ├── payroll/                 PayrollDashboard (pay now, advances, history)
    ├── staff/                   StaffManagement (add/edit, PIN setup, archive flow)
    ├── reports/                 ReportsScreen (shift/payroll/inventory/credit/expense)
    ├── expenses/                ExpensesScreen (CRUD, categories, date filter)
    ├── hardware/                HardwareConfig + FuelRate
    ├── settings/                SettingsScreen (Discord, Google Drive, logout)
    ├── worker/                  WorkerHome, NozzleEntry, ShiftExecution, MyEarnings
    └── creditor/                CreditorPortal (phone login, balance, ledger)

supabase/
├── migrations/
│   ├── 001_enable_rls.sql       Enable RLS on all tables
│   └── 002_rls_policies.sql     Full RLS policies + JWT helper functions
└── functions/
    ├── auth-login/              Validates credentials → returns Supabase JWT
    ├── auth-signup-dealer/      Creates station + owner → registers in central registry
    ├── create-staff/            Creates staff member with bcrypt password + salary
    └── set-user-pin/            Hashes PIN and saves to User table

registry_supabase/
└── registry_schema.sql          Central registry table for station_code → Supabase URL

android/                         Android platform files (minSdk 23)
ios/                             iOS platform files (min iOS 13.0)
macos/                           macOS platform files (min 10.14)
windows/                         Windows runner (Win32 + Flutter)
```

---

## Troubleshooting

### "Station code not found"
- Check station is registered in central registry (registry Supabase)
- Verify `registrySupabaseUrl` in `app_constants.dart` points to correct project

### "Invalid credentials"
- Ensure `auth-login` edge function is deployed
- Check `INTERNAL_SALT` secret is set: `supabase secrets list`
- Verify User has `password_hash` set (bcrypt format)

### "RLS policy violation"
- Run migration `002_rls_policies.sql`
- Check user has `supabase_auth_id` set (migration `002` adds this column)
- Verify JWT includes `station_id` and `role` in `user_metadata`

### "Session creation failed"
- Deploy `auth-login` edge function
- Check edge function logs: `supabase functions logs auth-login --tail`

### Google Sign-In fails
- Verify SHA-1 fingerprint in Google Cloud Console matches your build
- Ensure `google-services.json` is in `android/app/`
- Enable Google Drive API in Google Cloud Console

---

## License

Proprietary. All rights reserved.
