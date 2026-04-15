# Graph Report - .  (2026-04-15)

## Corpus Check
- Corpus is ~13,153 words - fits in a single context window. You may not need a graph.

## Summary
- 184 nodes · 182 edges · 35 communities detected
- Extraction: 47% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.9)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_App Shell & Feature Index|App Shell & Feature Index]]
- [[_COMMUNITY_Dashboard & Staff Management|Dashboard & Staff Management]]
- [[_COMMUNITY_Auth & Core Services|Auth & Core Services]]
- [[_COMMUNITY_Supabase Backend & Edge Functions|Supabase Backend & Edge Functions]]
- [[_COMMUNITY_Dealer Onboarding & Shifts|Dealer Onboarding & Shifts]]
- [[_COMMUNITY_Inventory & Settings|Inventory & Settings]]
- [[_COMMUNITY_macOS Platform Runner|macOS Platform Runner]]
- [[_COMMUNITY_Windows Flutter Window|Windows Flutter Window]]
- [[_COMMUNITY_Plugin Registration|Plugin Registration]]
- [[_COMMUNITY_Edge Function Handlers|Edge Function Handlers]]
- [[_COMMUNITY_Auth Routing|Auth Routing]]
- [[_COMMUNITY_iOS Test Suite|iOS Test Suite]]
- [[_COMMUNITY_macOS Window Setup|macOS Window Setup]]
- [[_COMMUNITY_LLDB Debug Helper|LLDB Debug Helper]]
- [[_COMMUNITY_Windows Utilities|Windows Utilities]]
- [[_COMMUNITY_Android Entry Point|Android Entry Point]]
- [[_COMMUNITY_Tank & Hardware Config|Tank & Hardware Config]]
- [[_COMMUNITY_Creditor Data Views|Creditor Data Views]]
- [[_COMMUNITY_Swift Plugin Registrant|Swift Plugin Registrant]]
- [[_COMMUNITY_Windows Entry Point|Windows Entry Point]]
- [[_COMMUNITY_Windows Plugin Registrant|Windows Plugin Registrant]]
- [[_COMMUNITY_Currency & Payments|Currency & Payments]]
- [[_COMMUNITY_Credit Customer|Credit Customer]]
- [[_COMMUNITY_Registry Service|Registry Service]]
- [[_COMMUNITY_Plugin Header|Plugin Header]]
- [[_COMMUNITY_Android App Build|Android App Build]]
- [[_COMMUNITY_Android Settings|Android Settings]]
- [[_COMMUNITY_Android Root Build|Android Root Build]]
- [[_COMMUNITY_Windows Utils Header|Windows Utils Header]]
- [[_COMMUNITY_Windows Win32 Window|Windows Win32 Window]]
- [[_COMMUNITY_Windows Plugin Header|Windows Plugin Header]]
- [[_COMMUNITY_Payment Provider|Payment Provider]]
- [[_COMMUNITY_Station Code Screen|Station Code Screen]]
- [[_COMMUNITY_Google Drive Integration|Google Drive Integration]]
- [[_COMMUNITY_Export Formats|Export Formats]]

## God Nodes (most connected - your core abstractions)
1. `FuelOS - Fuel Station Management System` - 33 edges
2. `AppDelegate` - 6 edges
3. `Supabase Edge Functions` - 5 edges
4. `GeneratedPluginRegistrant` - 4 edges
5. `json()` - 4 edges
6. `Per-Dealer Supabase Instance` - 4 edges
7. `RunnerTests` - 3 edges
8. `MainFlutterWindow` - 3 edges
9. `Supabase Backend (PostgreSQL + Auth)` - 3 edges
10. `Central Registry Supabase Project` - 3 edges

## Surprising Connections (you probably didn't know these)
- `FuelOS App Icon (Light Blue Lightning Bolt)` --describes--> `FuelOS - Fuel Station Management System`  [INFERRED]
  macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png → README.md
- `FuelOS Complete Setup Guide` --describes--> `FuelOS - Fuel Station Management System`  [EXTRACTED]
  docs/SETUP.md → README.md
- `Windows Platform (Win32 + Flutter)` --uses--> `Windows CMake Build Configuration`  [EXTRACTED]
  README.md → windows/CMakeLists.txt
- `Windows CMake Build Configuration` --references--> `Windows Runner CMake (Flutter Runner)`  [EXTRACTED]
  windows/CMakeLists.txt → windows/runner/CMakeLists.txt

## Hyperedges (group relationships)
- **Multi-tenant authentication flow** — AuthService, RegistryService, TenantService, AuthNotifier, AuthState, AuthUser [0.95]
- **Credit and ledger system** — CreditCustomer, CreditTransaction, CreditPayment, CreditManagementScreen, WhatsAppShare [0.9]
- **Fuel inventory and sales tracking** — Tank, Shift, NozzleEntry, FuelRate, FuelType, HardwareConfigScreen [0.9]
- **External service integrations** — DiscordService, ExportService, SettingsScreen, GoogleDriveIntegration [0.85]
- **Localization and data formatting** — IstTime, IndianCurrency, Validators, UserRole, FuelType [0.9]

## Communities

### Community 0 - "App Shell & Feature Index"
Cohesion: 0.06
Nodes (35): Adaptive Navigation (Desktop Sidebar / Mobile Bottom), Android Platform (minSdk 23), Authentication Feature (Splash, Login, Signup), Credit Management Feature, Creditor Portal Feature, Creditor Hub (Credit Customer Portal), Dashboard Feature (Manager KPI), Dealer Hub (Owner Portal) (+27 more)

### Community 1 - "Dashboard & Staff Management"
Cohesion: 0.18
Nodes (18): create-staff, currentUserProvider, stationNameProvider, CreditManagementScreen, DashboardScreen, PayrollDashboardScreen, ReportsScreen, StaffManagementScreen (+10 more)

### Community 2 - "Auth & Core Services"
Cohesion: 0.13
Nodes (17): AuthNotifier, AuthService, AuthState, AuthUser, DiscordService, ExportService, GoRouter Navigation, IstTime (+9 more)

### Community 3 - "Supabase Backend & Edge Functions"
Cohesion: 0.12
Nodes (16): auth-login Edge Function, auth-signup-dealer Edge Function, bcrypt Password Hashing (Compatibility Layer), Central Registry Supabase Project, create-staff Edge Function, Database Migrations (RLS + Auth), Per-Dealer Supabase Instance, Supabase Edge Functions (+8 more)

### Community 4 - "Dealer Onboarding & Shifts"
Cohesion: 0.21
Nodes (13): DealerSignupScreen, ExpensesScreen, PaymentReconciliationScreen, ShiftListScreen, DealerSetupService, Expense, Nozzle, NozzleEntry (+5 more)

### Community 5 - "Inventory & Settings"
Cohesion: 0.31
Nodes (9): SettingsScreen, TankDashboardScreen, DiscordService, GoogleDriveService, DipReading, FuelOrder, StockTransaction, Tank (+1 more)

### Community 6 - "macOS Platform Runner"
Cohesion: 0.29
Nodes (2): AppDelegate, FlutterAppDelegate

### Community 7 - "Windows Flutter Window"
Cohesion: 0.33
Nodes (1): FlutterWindow()

### Community 8 - "Plugin Registration"
Cohesion: 0.4
Nodes (2): GeneratedPluginRegistrant, -registerWithRegistry

### Community 9 - "Edge Function Handlers"
Cohesion: 0.4
Nodes (1): json()

### Community 10 - "Auth Routing"
Cohesion: 0.4
Nodes (5): authProvider, GoRouter, LoginScreen, SplashScreen, AuthService

### Community 11 - "iOS Test Suite"
Cohesion: 0.5
Nodes (2): RunnerTests, XCTestCase

### Community 12 - "macOS Window Setup"
Cohesion: 0.5
Nodes (2): MainFlutterWindow, NSWindow

### Community 13 - "LLDB Debug Helper"
Cohesion: 0.5
Nodes (2): handle_new_rx_page(), Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.

### Community 14 - "Windows Utilities"
Cohesion: 0.67
Nodes (2): GetCommandLineArguments(), Utf8FromUtf16()

### Community 15 - "Android Entry Point"
Cohesion: 0.67
Nodes (1): MainActivity

### Community 16 - "Tank & Hardware Config"
Cohesion: 0.67
Nodes (3): FuelType, HardwareConfigScreen, Tank

### Community 17 - "Creditor Data Views"
Cohesion: 0.67
Nodes (3): fuelos_creditor_balance, fuelos_creditor_lookup, CreditorPortalScreen

### Community 18 - "Swift Plugin Registrant"
Cohesion: 1.0
Nodes (0): 

### Community 19 - "Windows Entry Point"
Cohesion: 1.0
Nodes (0): 

### Community 20 - "Windows Plugin Registrant"
Cohesion: 1.0
Nodes (0): 

### Community 21 - "Currency & Payments"
Cohesion: 1.0
Nodes (2): IndianCurrency, PaymentRecord

### Community 22 - "Credit Customer"
Cohesion: 1.0
Nodes (2): CreditCustomer, CreditManagementScreen

### Community 23 - "Registry Service"
Cohesion: 1.0
Nodes (2): HardwareConfigScreen, RegistryService

### Community 24 - "Plugin Header"
Cohesion: 1.0
Nodes (0): 

### Community 25 - "Android App Build"
Cohesion: 1.0
Nodes (0): 

### Community 26 - "Android Settings"
Cohesion: 1.0
Nodes (0): 

### Community 27 - "Android Root Build"
Cohesion: 1.0
Nodes (0): 

### Community 28 - "Windows Utils Header"
Cohesion: 1.0
Nodes (0): 

### Community 29 - "Windows Win32 Window"
Cohesion: 1.0
Nodes (0): 

### Community 30 - "Windows Plugin Header"
Cohesion: 1.0
Nodes (0): 

### Community 31 - "Payment Provider"
Cohesion: 1.0
Nodes (1): PaymentProvider

### Community 32 - "Station Code Screen"
Cohesion: 1.0
Nodes (1): StationCodeScreen

### Community 33 - "Google Drive Integration"
Cohesion: 1.0
Nodes (1): Google Sign-In Setup (Drive Backup)

### Community 34 - "Export Formats"
Cohesion: 1.0
Nodes (1): Export Formats (PDF, CSV, WhatsApp)

## Knowledge Gaps
- **44 isolated node(s):** `-registerWithRegistry`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `FuelOS Complete Setup Guide`, `Flutter Cross-Platform Framework`, `auth-signup-dealer Edge Function` (+39 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Swift Plugin Registrant`** (2 nodes): `RegisterGeneratedPlugins()`, `GeneratedPluginRegistrant.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Entry Point`** (2 nodes): `wWinMain()`, `main.cpp`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Plugin Registrant`** (2 nodes): `RegisterPlugins()`, `generated_plugin_registrant.cc`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Currency & Payments`** (2 nodes): `IndianCurrency`, `PaymentRecord`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Credit Customer`** (2 nodes): `CreditCustomer`, `CreditManagementScreen`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Registry Service`** (2 nodes): `HardwareConfigScreen`, `RegistryService`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Plugin Header`** (1 nodes): `GeneratedPluginRegistrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android App Build`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android Settings`** (1 nodes): `settings.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Android Root Build`** (1 nodes): `build.gradle.kts`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Utils Header`** (1 nodes): `utils.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Win32 Window`** (1 nodes): `win32_window.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Windows Plugin Header`** (1 nodes): `generated_plugin_registrant.h`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Payment Provider`** (1 nodes): `PaymentProvider`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Station Code Screen`** (1 nodes): `StationCodeScreen`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Google Drive Integration`** (1 nodes): `Google Sign-In Setup (Drive Backup)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Export Formats`** (1 nodes): `Export Formats (PDF, CSV, WhatsApp)`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `FuelOS - Fuel Station Management System` connect `App Shell & Feature Index` to `Supabase Backend & Edge Functions`?**
  _High betweenness centrality (0.066) - this node is a cross-community bridge._
- **Why does `Supabase Backend (PostgreSQL + Auth)` connect `Supabase Backend & Edge Functions` to `App Shell & Feature Index`?**
  _High betweenness centrality (0.034) - this node is a cross-community bridge._
- **What connects `-registerWithRegistry`, `Intercept NOTIFY_DEBUGGER_ABOUT_RX_PAGES and touch the pages.`, `FuelOS Complete Setup Guide` to the rest of the system?**
  _44 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `App Shell & Feature Index` be split into smaller, more focused modules?**
  _Cohesion score 0.06 - nodes in this community are weakly interconnected._
- **Should `Auth & Core Services` be split into smaller, more focused modules?**
  _Cohesion score 0.13 - nodes in this community are weakly interconnected._
- **Should `Supabase Backend & Edge Functions` be split into smaller, more focused modules?**
  _Cohesion score 0.12 - nodes in this community are weakly interconnected._