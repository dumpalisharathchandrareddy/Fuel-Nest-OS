import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import '../models/auth_user.dart';

/// Manages the per-dealer Supabase client.
/// Each dealer has their own Supabase project.
/// This service stores and retrieves their connection details securely.
class TenantService {
  TenantService._();
  static final instance = TenantService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  SupabaseClient? _tenantClient;
  StationRegistryEntry? _currentStation;

  /// Get the current tenant's Supabase client.
  /// Throws if no tenant is configured.
  SupabaseClient get client {
    if (_tenantClient == null) {
      throw StateError(
        'No tenant configured. User must enter station code first.',
      );
    }
    return _tenantClient!;
  }

  StationRegistryEntry? get currentStation => _currentStation;
  bool get isConfigured => _tenantClient != null;

  /// Set up the tenant connection from registry entry.
  /// Called after station code lookup succeeds.
  Future<void> configure(StationRegistryEntry entry) async {
    // Store securely for next app launch
    await _storage.write(
      key: StorageKeys.tenantUrl,
      value: entry.supabaseUrl,
    );
    await _storage.write(
      key: StorageKeys.tenantAnonKey,
      value: entry.anonKey,
    );
    await _storage.write(
      key: StorageKeys.stationCode,
      value: entry.stationCode,
    );
    await _storage.write(
      key: StorageKeys.stationName,
      value: entry.stationName,
    );

    _currentStation = entry;
    _tenantClient = SupabaseClient(entry.supabaseUrl, entry.anonKey);
  }

  /// Configure with dummy credentials for UI testing/Demo Mode.
  void configureDemoMode() {
    _currentStation = const StationRegistryEntry(
      stationCode: 'DEMO001',
      stationName: 'FuelOS Demo Station',
      supabaseUrl: 'https://demo.supabase.co',
      anonKey: 'demo-anon-key',
    );
    _tenantClient = SupabaseClient(
      _currentStation!.supabaseUrl,
      _currentStation!.anonKey,
    );
  }

  /// Restore tenant connection from secure storage on app launch.
  /// Returns the stored station code if found.
  Future<String?> restoreFromStorage() async {
    final url = await _storage.read(key: StorageKeys.tenantUrl);
    final anonKey = await _storage.read(key: StorageKeys.tenantAnonKey);
    final stationCode = await _storage.read(key: StorageKeys.stationCode);
    final stationName = await _storage.read(key: StorageKeys.stationName);

    if (url == null || anonKey == null || stationCode == null) return null;

    _tenantClient = SupabaseClient(url, anonKey);
    _currentStation = StationRegistryEntry(
      stationCode: stationCode,
      stationName: stationName ?? '',
      supabaseUrl: url,
      anonKey: anonKey,
    );

    return stationCode;
  }

  /// Set the Supabase session after login/signup.
  /// Uses client.auth.setSession(refreshToken) which calls GoTrue's token
  /// endpoint and returns a full session — avoids the partial-JSON crash
  /// that recoverSession causes when the user object shape is wrong.
  Future<void> setSession(String accessToken, String refreshToken) async {
    await _storage.write(
      key: StorageKeys.userSession,
      value: refreshToken,
    );
    try {
      await client.auth.setSession(refreshToken);
    } catch (_) {
      // Non-fatal: app AuthUser is already persisted; GoTrue session is
      // best-effort for auto-refresh. Silently ignore if it fails.
    }
  }

  /// Restore the saved session on app resume.
  Future<bool> restoreSession() async {
    final saved = await _storage.read(key: StorageKeys.userSession);
    if (saved == null) return false;
    try {
      await client.auth.setSession(saved).timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clear all tenant data on logout.
  Future<void> clearTenant() async {
    try {
      await _tenantClient?.auth.signOut();
    } catch (_) {}
    // We KEEP _tenantClient and _currentStation in memory
    // so the station remains "configured" for the next login
    await _storage.delete(key: StorageKeys.userSession);
  }

  /// Full reset - clear everything including station code.
  Future<void> fullReset() async {
    await clearTenant();
    await _storage.deleteAll();
  }

  /// Returns a temporary SupabaseClient for [entry] without writing to secure
  /// storage or replacing the app-wide tenant client.
  /// Use this for read-only flows (e.g. creditor portal) that must not
  /// interfere with an active dealer/manager session.
  SupabaseClient createTemporaryClient(StationRegistryEntry entry) {
    return SupabaseClient(entry.supabaseUrl, entry.anonKey);
  }
}
