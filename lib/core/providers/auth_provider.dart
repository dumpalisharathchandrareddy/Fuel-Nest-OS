import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/auth_user.dart';
import '../services/auth_service.dart';

// ── Auth State ────────────────────────────────────────────────────────────────

class AuthState {
  final AuthUser? user;
  final bool isLoading;
  final String? error;
  final String? stationCode;
  final String? stationName;
  final bool stationConfigured;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.stationCode,
    this.stationName,
    this.stationConfigured = false,
  });

  bool get isLoggedIn => user != null;
  bool get isDealer => user?.isDealer ?? false;
  bool get isManager => user?.isManager ?? false;
  bool get isStaff => user?.isStaff ?? false;

  AuthState copyWith({
    AuthUser? user,
    bool? isLoading,
    String? error,
    String? stationCode,
    String? stationName,
    bool? stationConfigured,
  }) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        stationCode: stationCode ?? this.stationCode,
        stationName: stationName ?? this.stationName,
        stationConfigured: stationConfigured ?? this.stationConfigured,
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

  /// Step 2: Login as Dealer / Manager / Staff
  Future<bool> login({
    required String identifier,
    required String credential,
    required String role,
    bool isPin = false,
  }) async {
    state = state.withLoading();
    try {
      final user = await AuthService.instance.loginStaff(
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
