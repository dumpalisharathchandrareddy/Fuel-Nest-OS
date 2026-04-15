import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/providers/auth_provider.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/auth/screens/station_code_screen.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/dealer_signup_screen.dart';
import 'features/creditor/screens/creditor_portal_screen.dart';
import 'shared/layout/main_shell.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/shifts/screens/shift_list_screen.dart';
import 'features/shifts/screens/payment_reconciliation_screen.dart';
import 'features/inventory/screens/tank_dashboard_screen.dart';
import 'features/credit/screens/credit_management_screen.dart';
import 'features/payroll/screens/payroll_dashboard_screen.dart';
import 'features/staff/screens/staff_management_screen.dart';
import 'features/reports/screens/reports_screen.dart';
import 'features/expenses/screens/expenses_screen.dart';
import 'features/hardware/screens/hardware_config_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/worker/screens/worker_home_screen.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

GoRouter? _instance;

final routerProvider = Provider<GoRouter>((ref) {
  if (_instance != null) return _instance!;

  final notifier = ref.read(routerNotifierProvider);

  _instance = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: notifier,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loggedIn = auth.isLoggedIn;
      final stationSet = auth.stationConfigured;
      final loc = state.matchedLocation;

      debugPrint(
          'ROUTER REDIRECT: loc=$loc, stationSet=$stationSet, loggedIn=$loggedIn');

      if (loc == '/splash') {
        if (auth.isLoading) return null;
        // Proceed to check stationSet and loggedIn below
      }

      if (!stationSet) {
        if (loc == '/station' || loc == '/signup') return null;
        return '/station';
      }

      if (!loggedIn) {
        if (loc == '/login' || loc == '/signup' || loc == '/creditor') {
          return null;
        }
        return '/login';
      }

      if (loc == '/login' || loc == '/station' || loc == '/signup') {
        final dest =
            auth.user?.role == 'PUMP_PERSON' ? '/worker' : '/app/dashboard';
        return dest;
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/station', builder: (_, __) => const StationCodeScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const DealerSignupScreen()),
      GoRoute(
          path: '/creditor', builder: (_, __) => const CreditorPortalScreen()),
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
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) =>
            MainShell(state: state, child: child),
        routes: [
          GoRoute(
              path: '/app/dashboard',
              pageBuilder: (_, __) => _noTransition(const DashboardScreen())),
          GoRoute(
              path: '/app/shifts',
              pageBuilder: (_, __) => _noTransition(const ShiftListScreen())),
          GoRoute(
            path: '/app/shifts/payment/:shiftId',
            builder: (_, s) => PaymentReconciliationScreen(
                shiftId: s.pathParameters['shiftId']!),
          ),
          GoRoute(
              path: '/app/inventory',
              pageBuilder: (_, __) =>
                  _noTransition(const TankDashboardScreen())),
          GoRoute(
              path: '/app/inventory/order',
              builder: (_, __) => const FuelOrderScreen()),
          GoRoute(
              path: '/app/inventory/cheque',
              builder: (_, __) => const ChequeEntryScreen()),
          GoRoute(
              path: '/app/inventory/dip',
              builder: (_, __) => const DipReadingScreen()),
          GoRoute(
              path: '/app/credit',
              pageBuilder: (_, __) =>
                  _noTransition(const CreditManagementScreen())),
          GoRoute(
              path: '/app/payroll',
              pageBuilder: (_, __) =>
                  _noTransition(const PayrollDashboardScreen())),
          GoRoute(
              path: '/app/staff',
              pageBuilder: (_, __) =>
                  _noTransition(const StaffManagementScreen())),
          GoRoute(
              path: '/app/reports',
              pageBuilder: (_, __) => _noTransition(const ReportsScreen())),
          GoRoute(
              path: '/app/expenses',
              pageBuilder: (_, __) => _noTransition(const ExpensesScreen())),
          GoRoute(
              path: '/app/hardware',
              pageBuilder: (_, __) =>
                  _noTransition(const HardwareConfigScreen())),
          GoRoute(
              path: '/app/rates',
              pageBuilder: (_, __) => _noTransition(const FuelRateScreen())),
          GoRoute(
              path: '/app/settings',
              pageBuilder: (_, __) => _noTransition(const SettingsScreen())),
        ],
      ),
    ],
  );

  return _instance!;
});

NoTransitionPage<void> _noTransition(Widget child) =>
    NoTransitionPage(child: child);

final routerNotifierProvider = ChangeNotifierProvider<_RouterNotifier>((ref) {
  final notifier = _RouterNotifier();
  ref.listen<AuthState>(authProvider, (_, __) => notifier.trigger());
  return notifier;
});

class _RouterNotifier extends ChangeNotifier {
  void trigger() {
    debugPrint('ROUTER: Notifier triggered by auth change');
    notifyListeners();
  }
}
