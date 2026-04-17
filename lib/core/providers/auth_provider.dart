import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/auth_user.dart';
import '../services/auth_service.dart';
import '../services/tenant_service.dart';

// ── Auth State ────────────────────────────────────────────────────────────────

class AuthState {
  final AuthUser? user;
  final bool isLoading;
  final String? error;
  final String? stationCode;
  final String? stationName;
  final bool stationConfigured;
  final bool isDemoMode;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.stationCode,
    this.stationName,
    this.stationConfigured = false,
    this.isDemoMode = false,
  });

  bool get isLoggedIn => user != null;
  bool get isDealer => user?.isDealer ?? false;
  bool get isManager => user?.isManager ?? false;
  bool get isStaff => user?.isStaff ?? false;

  static const _unset = Object();

  // Passing error: null explicitly clears it; omitting error preserves it.
  AuthState copyWith({
    AuthUser? user,
    bool? isLoading,
    Object? error = _unset,
    String? stationCode,
    String? stationName,
    bool? stationConfigured,
    bool? isDemoMode,
  }) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: identical(error, _unset) ? this.error : error as String?,
        stationCode: stationCode ?? this.stationCode,
        stationName: stationName ?? this.stationName,
        stationConfigured: stationConfigured ?? this.stationConfigured,
        isDemoMode: isDemoMode ?? this.isDemoMode,
      );

  AuthState withError(String e) => copyWith(isLoading: false, error: e);
  AuthState withLoading() => copyWith(isLoading: true, error: null);
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  /// Called on app launch - restore saved session
  Future<void> initialize() async {
    state = state.withLoading();
    try {
      final user = await AuthService.instance.restoreSession();
      if (user != null) {
        state = AuthState(
          user: user,
          stationCode: user.stationCode,
          stationName: user.stationName,
          stationConfigured: true,
          isDemoMode: user.id == 'demo-user-id',
        );
      } else {
        state = const AuthState();
      }
    } catch (e) {
      state = const AuthState();
    }
  }

  /// Step 1: Enter station code → look up registry
  Future<void> configureStation(String code) async {
    state = state.withLoading();
    try {
      final name = await AuthService.instance.configureStation(code);
      state = state.copyWith(
        isLoading: false,
        stationCode: code.toUpperCase(),
        stationName: name,
        stationConfigured: true,
      );
    } catch (e) {
      state = state.withError(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Step 1b: Manual configuration for development
  Future<void> configureManual({required String url, required String key}) async {
    final entry = StationRegistryEntry(
      stationCode: 'MANUAL',
      stationName: 'Local Development Station',
      supabaseUrl: url,
      anonKey: key,
    );
    await TenantService.instance.configure(entry);
    state = state.copyWith(
      stationCode: 'MANUAL',
      stationName: 'Local Development Station',
      stationConfigured: true,
    );
  }

  /// Step 2: Unified login for all roles
  Future<bool> login({
    required String identifier,
    required String credential,
    required String role,
    bool isPin = false,
  }) async {
    state = state.withLoading();
    try {
      final user = await AuthService.instance.loginUnified(
        identifier: identifier,
        credential: credential,
        role: role,
        isPin: isPin,
      );
      state = AuthState(
        user: user,
        stationCode: user.stationCode,
        stationName: user.stationName,
        stationConfigured: true,
      );
      return true;
    } catch (e) {
      state = state.withError(e.toString().replaceAll('Exception: ', ''));
      return false;
    }
  }

  /// Dealer signup — calls DealerSetupService and updates auth state on success.
  Future<bool> signup({
    required String stationCode,
    required String stationName,
    required String ownerName,
    required String phone,
    required String password,
    String supabaseUrl = '',
    String anonKey = '',
    String dbMode = 'byo',
    String? city,
    String? state,
  }) async {
    this.state = this.state.withLoading();
    try {
      final user = await DealerSetupService.instance.signupDealer(
        stationCode: stationCode,
        stationName: stationName,
        ownerName: ownerName,
        phone: phone,
        password: password,
        supabaseUrl: supabaseUrl,
        anonKey: anonKey,
        dbMode: dbMode,
        city: city,
        state: state,
      );
      this.state = AuthState(
        user: user,
        stationCode: user.stationCode,
        stationName: user.stationName,
        stationConfigured: true,
      );
      return true;
    } catch (e) {
      this.state =
          this.state.withError(e.toString().replaceAll('Exception: ', ''));
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    await AuthService.instance.logout();
    state = AuthState(
      stationCode: state.stationCode, // keep station code
      stationName: state.stationName,
      stationConfigured: state.stationConfigured,
    );
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void enterDemoMode() {
    TenantService.instance.configureDemoMode();
    state = AuthState(
      isDemoMode: true,
      stationConfigured: true,
      stationCode: 'DEMO001',
      stationName: 'FuelOS Demo Station',
      user: const AuthUser(
        id: 'demo-user-id',
        stationId: 'demo-station-id',
        stationCode: 'DEMO001',
        stationName: 'FuelOS Demo Station',
        role: 'MANAGER',
        fullName: 'Demo Manager',
      ),
    );
  }

  void clearStation() {
    state = const AuthState();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

final currentUserProvider = Provider<AuthUser?>((ref) {
  return ref.watch(authProvider).user;
});

final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isLoggedIn;
});

final stationNameProvider = Provider<String>((ref) {
  return ref.watch(authProvider).stationName ?? '';
});
