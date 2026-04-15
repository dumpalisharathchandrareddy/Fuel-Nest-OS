import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/providers/auth_provider.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/station_code_screen.dart';
import 'features/auth/screens/role_select_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/dealer_signup_screen.dart';
import 'features/creditor/screens/creditor_portal_screen.dart';
import 'shared/layout/main_shell.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/shifts/screens/shift_list_screen.dart';
import 'features/shifts/screens/payment_reconciliation_screen.dart';
import 'features/inventory/screens/tank_dashboard_screen.dart';
import 'features/inventory/screens/fuel_order_screen.dart';
import 'features/inventory/screens/cheque_entry_screen.dart';
import 'features/inventory/screens/dip_reading_screen.dart';
import 'features/credit/screens/credit_management_screen.dart';
import 'features/payroll/screens/payroll_dashboard_screen.dart';
import 'features/staff/screens/staff_management_screen.dart';
import 'features/reports/screens/reports_screen.dart';
import 'features/expenses/screens/expenses_screen.dart';
import 'features/hardware/screens/hardware_config_screen.dart';
import 'features/fuel_rates/screens/fuel_rate_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/worker/screens/worker_home_screen.dart';
import 'features/worker/screens/nozzle_entry_screen.dart';
import 'features/worker/screens/shift_execution_screen.dart';
import 'features/worker/screens/my_earnings_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  // Use a notifier that GoRouter can listen to for rebuilds
  final notifier = _RouterNotifier(ref);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final loggedIn = auth.isLoggedIn;
      final stationSet = auth.stationConfigured;
      final loc = state.matchedLocation;

      // Always allow splash
      if (loc == '/splash') return null;

      // Not configured → station code screen
      if (!stationSet && loc != '/station' && loc != '/signup') {
        return '/station';
      }

      // Configured but not logged in → role select
      if (stationSet && !loggedIn &&
          !loc.startsWith('/login') &&
          !loc.startsWith('/signup') &&
          !loc.startsWith('/creditor')) {
        return '/login';
      }

      // Logged in → redirect from auth screens to home
      if (loggedIn &&
          (loc == '/login' ||
              loc == '/station' ||
              loc.startsWith('/login/'))) {
        final role = auth.user!.role;
        if (role == 'PUMP_PERSON') return '/worker';
        return '/app/dashboard';
      }

      return null;
    },
    routes: [
      // ── Auth flow ──────────────────────────────────────────────────────
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/station', builder: (_, __) => const StationCodeScreen()),
      GoRoute(path: '/login', builder: (_, __) => const RoleSelectScreen()),
      GoRoute(
        path: '/login/dealer',
        builder: (_, __) => const LoginScreen(role: 'DEALER'),
      ),
      GoRoute(
        path: '/login/manager',
        builder: (_, __) => const LoginScreen(role: 'MANAGER'),
      ),
      GoRoute(
        path: '/login/staff',
        builder: (_, __) => const LoginScreen(role: 'PUMP_PERSON'),
      ),
      GoRoute(path: '/signup', builder: (_, __) => const DealerSignupScreen()),

      // ── Creditor portal (standalone, no main shell) ────────────────────
      GoRoute(
        path: '/creditor',
        builder: (_, __) => const CreditorPortalScreen(),
      ),

      // ── Worker Hub (standalone, simple UI) ────────────────────────────
      GoRoute(path: '/worker', builder: (_, __) => const WorkerHomeScreen()),
      GoRoute(
        path: '/worker/nozzle/:pumpId',
        builder: (_, s) =>
            NozzleEntryScreen(pumpId: s.pathParameters['pumpId']!),
      ),
      GoRoute(
        path: '/worker/shift/:shiftId',
        builder: (_, s) =>
            ShiftExecutionScreen(shiftId: s.pathParameters['shiftId']!),
      ),
      GoRoute(
        path: '/worker/earnings',
        builder: (_, __) => const MyEarningsScreen(),
      ),

      // ── Manager / Dealer Hub (with nav shell) ─────────────────────────
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (_, __, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/app/dashboard',
            pageBuilder: (_, __) => _noTransition(const DashboardScreen()),
          ),
          GoRoute(
            path: '/app/shifts',
            pageBuilder: (_, __) => _noTransition(const ShiftListScreen()),
          ),
          GoRoute(
            path: '/app/shifts/payment/:shiftId',
            builder: (_, s) => PaymentReconciliationScreen(
              shiftId: s.pathParameters['shiftId']!,
            ),
          ),
          GoRoute(
            path: '/app/inventory',
            pageBuilder: (_, __) => _noTransition(const TankDashboardScreen()),
          ),
          GoRoute(
            path: '/app/inventory/order',
            builder: (_, __) => const FuelOrderScreen(),
          ),
          GoRoute(
            path: '/app/inventory/cheque',
            builder: (_, __) => const ChequeEntryScreen(),
          ),
          GoRoute(
            path: '/app/inventory/dip',
            builder: (_, __) => const DipReadingScreen(),
          ),
          GoRoute(
            path: '/app/credit',
            pageBuilder: (_, __) =>
                _noTransition(const CreditManagementScreen()),
          ),
          GoRoute(
            path: '/app/payroll',
            pageBuilder: (_, __) =>
                _noTransition(const PayrollDashboardScreen()),
          ),
          GoRoute(
            path: '/app/staff',
            pageBuilder: (_, __) =>
                _noTransition(const StaffManagementScreen()),
          ),
          GoRoute(
            path: '/app/reports',
            pageBuilder: (_, __) => _noTransition(const ReportsScreen()),
          ),
          GoRoute(
            path: '/app/expenses',
            pageBuilder: (_, __) => _noTransition(const ExpensesScreen()),
          ),
          GoRoute(
            path: '/app/hardware',
            pageBuilder: (_, __) =>
                _noTransition(const HardwareConfigScreen()),
          ),
          GoRoute(
            path: '/app/rates',
            pageBuilder: (_, __) => _noTransition(const FuelRateScreen()),
          ),
          GoRoute(
            path: '/app/settings',
            pageBuilder: (_, __) => _noTransition(const SettingsScreen()),
          ),
        ],
      ),
    ],
  );
});

NoTransitionPage<void> _noTransition(Widget child) =>
    NoTransitionPage(child: child);

// ── Router notifier - bridges Riverpod to GoRouter refreshListenable ──────────

class _RouterNotifier extends ChangeNotifier {
  late final Ref _ref;
  _RouterNotifier(Ref ref) {
    _ref = ref;
    ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}
