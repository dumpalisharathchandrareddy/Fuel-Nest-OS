import 'package:flutter/foundation.dart';
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

  // ── Defensive Storage Helpers ─────────────────────────────────────────────
  
  Future<String?> _read(String key) async {
    try {
      debugPrint('[TENANT] 🔍 Reading key: $key...');
      final value = await _storage.read(key: key).timeout(const Duration(seconds: 15));
      debugPrint('[TENANT] ✅ Read $key: ${value != null ? "FOUND" : "NOT FOUND"}');
      return value;
    } catch (e) {
      debugPrint('[TENANT] ❌ Error reading key $key: $e');
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      debugPrint('[TENANT] 💾 Writing key: $key...');
      await _storage.write(key: key, value: value).timeout(const Duration(seconds: 15));
      debugPrint('[TENANT] ✅ Written $key');
    } catch (e) {
      debugPrint('[TENANT] ❌ Error writing key $key: $e');
    }
  }

  Future<void> _delete(String key) async {
    try {
      debugPrint('[TENANT] 🗑️ Deleting key: $key...');
      await _storage.delete(key: key).timeout(const Duration(seconds: 15));
      debugPrint('[TENANT] ✅ Deleted $key');
    } catch (e) {
      debugPrint('[TENANT] ❌ Error deleting key $key: $e');
    }
  }

  Future<void> _deleteAll() async {
    try {
      debugPrint('[TENANT] 🧹 Clearing all storage...');
      await _storage.deleteAll().timeout(const Duration(seconds: 15));
      debugPrint('[TENANT] ✅ Storage cleared');
    } catch (e) {
      debugPrint('[TENANT] ❌ Error clearing storage: $e');
    }
  }

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
    await _write(StorageKeys.tenantUrl, entry.supabaseUrl);
    await _write(StorageKeys.tenantAnonKey, entry.anonKey);
    await _write(StorageKeys.stationCode, entry.stationCode);
    await _write(StorageKeys.stationName, entry.stationName);

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
    debugPrint('[TENANT] 🔄 Beginning technical restoration...');
    final url = await _read(StorageKeys.tenantUrl);
    final anonKey = await _read(StorageKeys.tenantAnonKey);
    final stationCode = await _read(StorageKeys.stationCode);
    final stationName = await _read(StorageKeys.stationName);

    debugPrint('[TENANT] 📊 Probe results: URL=${url != null}, Key=${anonKey != null}, Code=$stationCode, Name=${stationName != null}');

    if (url == null || anonKey == null || stationCode == null) {
      if (url != null || anonKey != null || stationCode != null) {
        debugPrint('[TENANT] ⚠️ Partial station config found. Triggering technical reset.');
        await fullReset();
      }
      debugPrint('[TENANT] 🏁 Restoration complete: No valid station found.');
      return null;
    }

    _tenantClient = SupabaseClient(url, anonKey);
    _currentStation = StationRegistryEntry(
      stationCode: stationCode,
      stationName: stationName ?? '',
      supabaseUrl: url,
      anonKey: anonKey,
    );

    debugPrint('[AUTH_DEBUG] Technical restoration success for station $stationCode');
    return stationCode;
  }

  /// Set the Supabase session after login/signup.
  /// Uses client.auth.setSession(refreshToken) which calls GoTrue's token
  /// endpoint and returns a full session — avoids the partial-JSON crash
  /// that recoverSession causes when the user object shape is wrong.
  Future<void> setSession(String accessToken, String refreshToken) async {
    await _write(StorageKeys.userSession, refreshToken);
    try {
      await client.auth.setSession(refreshToken);
    } catch (_) {
      // Non-fatal: app AuthUser is already persisted; GoTrue session is
      // best-effort for auto-refresh. Silently ignore if it fails.
    }
  }

  /// Restore the saved session on app resume.
  Future<bool> restoreSession() async {
    final saved = await _read(StorageKeys.userSession);
    if (saved == null) {
      debugPrint('[AUTH_DEBUG] restoreSession: No refresh token found in storage.');
      return false;
    }
    
    debugPrint('[AUTH_DEBUG] restoreSession: Found token (len=${saved.length}). Attempting Supabase setSession...');
    
    try {
      final response = await client.auth
          .setSession(saved)
          .timeout(const Duration(seconds: 10));
      
      final hasSession = response.session != null;
      debugPrint('[AUTH_DEBUG] restoreSession: Supabase response received. SessionPresent=$hasSession');
      return hasSession;
    } catch (e) {
      debugPrint('[AUTH_DEBUG] restoreSession: Sync failed with error: $e');
      return false;
    }
  }

  /// Clear all tenant data on logout.
  Future<void> clearTenant() async {
    try {
      await _tenantClient?.auth.signOut();
    } catch (_) {}
    await clearUserSession();
  }

  /// Explicitly clear ONLY the user-level session data (tokens).
  /// Preserves station configuration.
  Future<void> clearUserSession() async {
    debugPrint('[AUTH_DEBUG] clearUserSession: Removing refresh token from storage.');
    await _delete(StorageKeys.userSession);
  }

  /// Full reset - clear everything including station code.
  Future<void> fullReset() async {
    debugPrint('TENANT_RESET: Performing full cleanup of station and session data.');
    await clearTenant();
    await _deleteAll();
    _tenantClient = null;
    _currentStation = null;
  }

  /// Returns a temporary SupabaseClient for [entry] without writing to secure
  /// storage or replacing the app-wide tenant client.
  /// Use this for read-only flows (e.g. creditor portal) that must not
  /// interfere with an active dealer/manager session.
  SupabaseClient createTemporaryClient(StationRegistryEntry entry) {
    return SupabaseClient(entry.supabaseUrl, entry.anonKey);
  }
}
