import 'package:flutter/foundation.dart';
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
  final String loadingStage;

  const AuthState({
    this.user,
    this.isLoading = true, // Default to true for deterministic startup
    this.error,
    this.stationCode,
    this.stationName,
    this.stationConfigured = false,
    this.isDemoMode = false,
    this.loadingStage = 'Starting...',
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
    String? loadingStage,
  }) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: identical(error, _unset) ? this.error : error as String?,
        stationCode: stationCode ?? this.stationCode,
        stationName: stationName ?? this.stationName,
        stationConfigured: stationConfigured ?? this.stationConfigured,
        isDemoMode: isDemoMode ?? this.isDemoMode,
        loadingStage: loadingStage ?? this.loadingStage,
      );

  AuthState withError(String e) => copyWith(isLoading: false, error: e);
  AuthState withLoading() => copyWith(isLoading: true, error: null);
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  bool _isInitializing = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Called once at provider creation - restore saved technical + user state
  Future<void> initialize() async {
    // 1. Guard against concurrent calls or call after disposal
    if (_isInitializing) {
      debugPrint('[STARTUP] ✋ initialize skipped (already running)');
      return;
    }
    if (_disposed) {
      debugPrint('[STARTUP] 🛑 initialize aborted (disposed)');
      return;
    }

    _isInitializing = true;
    debugPrint('[STARTUP] 🚀 initialize called');

    // Ensure we start in loading state
    if (!_disposed) {
      state = state.copyWith(isLoading: true, error: null);
    }

    // Global fail-safe: Force-clear loading after 45 seconds no matter what
    final failSafeTimer = Future.delayed(const Duration(seconds: 45)).then((_) {
      if (!_disposed && mounted && state.isLoading) {
        debugPrint('[STARTUP] 🛡️ Global Fail-Safe Triggered! Breaking loading lock.');
        state = state.copyWith(isLoading: false, loadingStage: 'Ready (Fail-Safe)');
      }
    });

    try {
      if (_disposed) return;
      debugPrint('[STARTUP] 🛰️ Beginning restoration sequence...');
      state = state.copyWith(loadingStage: 'Probing station storage...');

      // Stage 1: Technical restoration (Quick Probe)
      if (_disposed) return;
      debugPrint('[STARTUP] Stage 1/3: Quick-probing station technical config from storage...');
      final stationCode = await TenantService.instance.restoreFromStorage()
          .timeout(const Duration(seconds: 3), onTimeout: () {
            debugPrint('[STARTUP] ⚠️ Stage 1 restoration timed out (3s Quick Probe).');
            return null;
          });

      if (_disposed) return;

      if (stationCode == null) {
        debugPrint('[STARTUP] 🏁 [CASE A] No station found. Sending to setup.');
        state = state.copyWith(
          isLoading: false,
          user: null,
          stationCode: null,
          stationName: null,
          stationConfigured: false,
          loadingStage: 'Ready',
        );
        return;
      }

      final curStation = TenantService.instance.currentStation;
      if (curStation == null) {
        debugPrint('[STARTUP] ⚠️ Technical mismatch in registry. Resetting.');
        await TenantService.instance.fullReset();
        if (!_disposed) {
          state = state.copyWith(
            isLoading: false,
            user: null,
            stationCode: null,
            stationName: null,
            stationConfigured: false,
            loadingStage: 'Ready',
          );
        }
        return;
      }

      debugPrint('[STARTUP] ✅ Stage 1 SUCCESS: Station ${curStation.stationCode} restored.');
      if (!_disposed) {
        state = state.copyWith(loadingStage: 'Syncing user session...');
      }

      // Stage 2: User restoration (AuthUser + Supabase technical sync)
      if (_disposed) return;
      debugPrint('[STARTUP] Stage 2/3: Probing user session and Supabase connection...');
      final user = await AuthService.instance.restoreSession()
          .timeout(const Duration(seconds: 30), onTimeout: () {
            debugPrint('[STARTUP] ⚠️ Stage 2 restoration timed out (30s Network/Sync).');
            return null;
          });

      if (_disposed) return;

      if (user != null) {
        debugPrint('[STARTUP] 🏁 [CASE C] Session restored for ${user.fullName}.');
        state = state.copyWith(
          user: user,
          stationCode: user.stationCode,
          stationName: user.stationName,
          stationConfigured: true,
          isDemoMode: user.id == 'demo-user-id' || user.id == 'dev-user-id',
          isLoading: false,
          loadingStage: 'Ready',
        );
      } else {
        debugPrint('[STARTUP] 🏁 [CASE B] Station found but session invalid/expired. Sending to login.');
        state = state.copyWith(
          stationCode: curStation.stationCode,
          stationName: curStation.stationName,
          stationConfigured: true,
          isLoading: false,
          loadingStage: 'Ready',
        );
      }
      debugPrint('[STARTUP] ✅ Stage 3/3 SUCCESS: Initialization sequence COMPLETE.');
    } catch (e, stack) {
      debugPrint('[STARTUP] ❌ Critical failure during initialization: $e');
      debugPrint('[STARTUP] StackTrace: $stack');
      if (!_disposed) {
        state = state.copyWith(isLoading: false, error: 'Initialization failed: $e');
      }
    } finally {
      _isInitializing = false;
      // Emergency guard: always ensure isLoading is false if we reach here
      if (!_disposed && state.isLoading) {
        debugPrint('[STARTUP] 🛡️ Emergency finally-block loading clearance triggered.');
        state = state.copyWith(isLoading: false);
      }
      debugPrint('[STARTUP] 🏁 initialize complete (isLoading=${_disposed ? "DISPOSED" : state.isLoading}, stationSet=${_disposed ? "DISPOSED" : state.stationConfigured})');
    }
  }

  /// Step 1: Enter station code → look up registry
  Future<void> configureStation(String code) async {
    state = state.withLoading();
    try {
      final name = await AuthService.instance.configureStation(code);
      if (!_disposed) {
        state = state.copyWith(
          isLoading: false,
          stationCode: code.toUpperCase(),
          stationName: name,
          stationConfigured: true,
        );
      }
    } catch (e) {
      if (!_disposed) {
        state = state.withError(e.toString().replaceAll('Exception: ', ''));
      }
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
    if (!_disposed) {
      state = state.copyWith(
        stationCode: 'MANUAL',
        stationName: 'Local Development Station',
        stationConfigured: true,
      );
    }
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
      if (!_disposed) {
        state = state.copyWith(
          user: user,
          stationCode: user.stationCode,
          stationName: user.stationName,
          stationConfigured: true,
          isLoading: false,
        );
      }
      return true;
    } catch (e) {
      if (!_disposed) {
        state = state.withError(e.toString().replaceAll('Exception: ', ''));
      }
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
      if (!_disposed) {
        this.state = this.state.copyWith(
          user: user,
          stationCode: user.stationCode,
          stationName: user.stationName,
          stationConfigured: true,
          isLoading: false,
        );
      }
      return true;
    } catch (e) {
      if (!_disposed) {
        this.state =
            this.state.withError(e.toString().replaceAll('Exception: ', ''));
      }
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    debugPrint('AUTH: Logging out user ${state.user?.fullName}');
    await AuthService.instance.logout();
    if (!_disposed) {
      state = state.copyWith(
        user: null, // Clear user/tokens
        isLoading: false,
      );
    }
  }

  void clearError() {
    if (!_disposed) {
      state = state.copyWith(error: null);
    }
  }

  void enterDemoMode() {
    TenantService.instance.configureDemoMode();
    if (!_disposed) {
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
  }

  Future<void> clearStation() async {
    await TenantService.instance.fullReset();
    if (!_disposed) {
      state = const AuthState();
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier();
  // Centralized Boot Ownership: Trigger exactly once on creation
  Future.microtask(() => notifier.initialize());
  return notifier;
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
