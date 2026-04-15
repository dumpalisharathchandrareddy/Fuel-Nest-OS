# FuelOS — Complete Setup Guide

> **Stack**: Flutter 3.x · Supabase (per-dealer) · No Express server · Direct DB

---

## Architecture Overview

```
FuelOS App (Flutter)
  ├── Auth: Supabase Edge Functions (2 functions only)
  ├── Data: Direct Supabase queries (RLS enforced)
  ├── PDF: On-device (pdf package)
  ├── Excel: On-device (syncfusion_flutter_xlsio)
  ├── Discord: Direct HTTP POST
  └── Google Drive: Direct OAuth in-app

Central Registry (Your Supabase)
  └── station_registry table: station_code → dealer's Supabase URL

Per-Dealer Supabase (each dealer's own project)
  ├── PostgreSQL DB (existing schema)
  ├── Edge Functions: auth-login, auth-signup-dealer
  └── Storage: receipts, reports (optional)
```

---

## Step 1 — Set Up the Central Registry (One Time, You Do This)

1. Create a **new Supabase project** at [supabase.com](https://supabase.com)  
   This is YOUR project — dealers never touch it.

2. Run the registry schema:
   ```bash
   # In your registry Supabase SQL editor:
   # Paste and run: registry_supabase/registry_schema.sql
   ```

3. Get the project URL and anon key from **Project Settings → API**.

4. Update `lib/core/constants/app_constants.dart`:
   ```dart
   static const registrySupabaseUrl = 'https://YOUR_REGISTRY_PROJECT.supabase.co';
   static const registryAnonKey = 'YOUR_REGISTRY_ANON_KEY';
   ```

---

## Step 2 — Set Up Each Dealer's Supabase

Each dealer creates their own free Supabase project. You (or they) run the setup once.

### 2a. Create Supabase Project
1. Go to [supabase.com](https://supabase.com) → New Project
2. Note the **Project URL** and **Anon Key** (Project Settings → API)
3. Note the **Service Role Key** (keep this secret — only used in edge functions)

### 2b. Run Database Migrations
In the Supabase SQL Editor, run these in order:

```bash
# 1. Your existing schema (from PMS-main/backend/prisma/...)
#    Run the Prisma-generated SQL or use db push

# 2. Enable RLS
supabase/migrations/001_enable_rls.sql

# 3. Add Flutter auth support + RLS policies
supabase/migrations/002_rls_policies.sql
```

### 2c. Deploy Edge Functions
```bash
# Install Supabase CLI
npm install -g supabase

# Login
supabase login

# Link to dealer's project
supabase link --project-ref YOUR_DEALER_PROJECT_REF

# Set environment variables (secrets)
supabase secrets set INTERNAL_SALT="your_random_secret_salt_here"

# Deploy auth functions
supabase functions deploy auth-login
supabase functions deploy auth-signup-dealer
```

### 2d. Dealer Setup in App
The dealer opens FuelOS and:
1. Taps **"New dealer? Register your station"**
2. **Step 0**: Enters their Supabase URL + anon key
3. **Step 1**: Sets station code (e.g. `RAMFUELS01`) and station name
4. **Step 2**: Creates owner account (name, phone, password)

This calls `auth-signup-dealer` edge function which:
- Creates the `FuelStation` record
- Creates the owner `User` record
- Returns a session token

Then registers in your central registry automatically.

---

## Step 3 — Build the Flutter App

```bash
# Install Flutter (if not already)
# https://flutter.dev/docs/get-started/install

# Get dependencies
cd fuelnest
flutter pub get

# Run on Android
flutter run -d android

# Run on Windows
flutter run -d windows

# Build APK (Android)
flutter build apk --release

# Build Windows installer
flutter build windows --release
```

### Android Setup (for Google Sign-In)
1. Add your app's SHA-1 fingerprint to Firebase/Google Console
2. Update `android/app/google-services.json` with your Firebase config
3. Or use the OAuth client ID from Google Cloud Console

### iOS Setup
```bash
flutter build ios --release
```
Add `GoogleService-Info.plist` from Google Cloud Console to `ios/Runner/`.

---

## Step 4 — Configure Each Hub

### Manager/Staff account creation
- Log in as Dealer
- Go to **Staff Management** → Add Staff
- Set role (Manager / Staff), name, phone, employee ID, PIN

### Initial Hardware Setup
- Go to **Hardware** → Add pumps and nozzles
- Go to **Inventory** → Set initial tank stock
- Go to **Rates** → Set fuel rates per litre

### Discord Setup (Optional but Recommended)
1. Create a Discord server → Add a channel → Edit channel → Integrations → Create Webhook
2. Copy the webhook URL
3. In FuelOS → Settings → Discord → Paste URL → Save → Test

### Google Drive Backup (Dealer Only)
1. In FuelOS → Settings → scroll to "Google Drive"
2. Tap **Connect Google Drive**
3. Sign in with Google account
4. Backups go to `FuelOS Backups/` folder in Drive

---

## User Login Guide

| Hub | What to Enter | How |
|---|---|---|
| **Dealer** | Station Code → Password | Settings → full access |
| **Manager** | Station Code → Username → PIN/Password | Daily ops |
| **Staff** | Station Code → Employee ID → PIN | Pump entry only |
| **Creditor** | Station Code → Mobile Number | Balance only |

---

## Database Notes

### Existing Schema Compatibility
FuelOS uses your existing Prisma schema tables unchanged. Only two additions:
- `User.supabase_auth_id` — links to Supabase Auth (added by migration 002)
- `User.pin_hash` — for PIN login (added by migration 002)

### Password Migration
Existing `password_hash` values (bcrypt from Node.js) work directly with the Edge Function's `bcrypt.compare()`. No migration needed.

### PIN Setup
To set a PIN for existing users, from manager dashboard:
```sql
-- Run in Supabase SQL editor to set a PIN for a staff member
-- The edge function handles this via the app UI
UPDATE "User"
SET pin_hash = crypt('1234', gen_salt('bf'))
WHERE employee_id = 'EMP001';
```

---

## Export Formats (Per Screen)

| Screen | PDF | Excel | CSV | WhatsApp | Discord |
|---|---|---|---|---|---|
| Shift | ✅ Full report | ✅ | ✅ | ✅ Summary | ✅ On settle |
| Inventory | ✅ Tank + orders | ✅ | ✅ | — | ✅ On delivery |
| Payroll | ✅ Pay slips | ✅ | ✅ | ✅ | ✅ On payout |
| Credit | ✅ Statement | ✅ | ✅ | ✅ | — |
| Reports | ✅ | ✅ | ✅ | — | — |
| Expenses | ✅ | ✅ | ✅ | — | — |

---

## Environment Variables (Edge Functions)

| Variable | Description | Required |
|---|---|---|
| `SUPABASE_URL` | Auto-set by Supabase | ✅ |
| `SUPABASE_SERVICE_ROLE_KEY` | Auto-set by Supabase | ✅ |
| `SUPABASE_ANON_KEY` | Auto-set by Supabase | ✅ |
| `INTERNAL_SALT` | Your secret salt for internal passwords | ✅ Set manually |

Set with:
```bash
supabase secrets set INTERNAL_SALT="any_random_string_keep_secret"
```

---

## Troubleshooting

### "Station not found"
- Station code is case-sensitive (always UPPERCASE)
- Check that the station was registered in the central registry
- Verify the registry Supabase URL/key in `app_constants.dart`

### "Invalid credentials"  
- Password may need to be re-set (old bcrypt from Node.js is compatible, but verify)
- Check the `INTERNAL_SALT` env var is set in edge functions

### "Session creation failed"
- Deploy edge functions: `supabase functions deploy auth-login`
- Check edge function logs: `supabase functions logs auth-login`

### RLS errors ("violates row-level security policy")
- Run migration 002 to create RLS policies
- Check `fuelos_station_id()` returns the correct station ID
- Verify JWT user_metadata has `station_id` set

---

## File Structure

```
fuelnest/
├── lib/
│   ├── main.dart                  App entry
│   ├── app.dart                   Router
│   ├── core/
│   │   ├── constants/             Colors, fuel types, storage keys
│   │   ├── models/                Data models (Shift, Tank, etc.)
│   │   ├── providers/             Riverpod auth state
│   │   ├── services/              Supabase, Discord, Drive, Export
│   │   └── utils/                 IST time, Indian currency
│   ├── shared/
│   │   ├── theme/                 Dark theme
│   │   ├── widgets/               Reusable UI components
│   │   └── layout/                Navigation shell
│   └── features/
│       ├── auth/                  Splash, station code, login, signup
│       ├── dashboard/             Manager/dealer overview
│       ├── shifts/                Shift list + reconciliation
│       ├── inventory/             Tanks, orders, cheques, dip readings
│       ├── credit/                Credit customer management
│       ├── payroll/               Salary payouts
│       ├── staff/                 Staff management
│       ├── reports/               Report generation
│       ├── expenses/              Daily expenses
│       ├── hardware/              Pumps, nozzles, tanks config
│       ├── fuel_rates/            Rate management
│       ├── settings/              Discord, Google Drive, app info
│       ├── worker/                Staff hub (nozzle entry, earnings)
│       └── creditor/              Credit balance portal
├── supabase/
│   ├── migrations/                SQL to run on each dealer's DB
│   └── functions/                 Edge Functions (auth-login, auth-signup)
└── registry_supabase/
    └── registry_schema.sql        SQL for your central registry
```

---

## India-Specific Notes

- All amounts: Indian Rupees (₹) with lakh/crore formatting
- All timestamps: stored UTC, displayed IST (Asia/Kolkata, UTC+5:30)
- Numbers: Indian format (e.g. ₹1,23,456 not ₹123,456)
- Phone numbers: 10-digit Indian mobile
- No App Store or Play Store required — APK sideload for Android, Windows installer for desktop
