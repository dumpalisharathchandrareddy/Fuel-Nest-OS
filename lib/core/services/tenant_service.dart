import 'dart:convert';

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

    if (url == null || anonKey == null || stationCode == null) return null;

    _tenantClient = SupabaseClient(url, anonKey);
    _currentStation = StationRegistryEntry(
      stationCode: stationCode,
      stationName: '', // loaded later from DB
      supabaseUrl: url,
      anonKey: anonKey,
    );

    return stationCode;
  }

  /// Set the Supabase session (access + refresh token) after login.
  Future<void> setSession(String accessToken, String refreshToken) async {
    await _storage.write(
      key: StorageKeys.userSession,
      value: '$accessToken|$refreshToken',
    );
    // recoverSession sets both tokens so the client can auto-refresh on expiry
    await client.auth.recoverSession(_sessionJson(accessToken, refreshToken));
  }

  /// Restore the saved session on app resume.
  Future<bool> restoreSession() async {
    final saved = await _storage.read(key: StorageKeys.userSession);
    if (saved == null) return false;
    final parts = saved.split('|');
    if (parts.length < 2) return false;
    try {
      await client.auth
          .recoverSession(_sessionJson(parts[0], parts[1]))
          .timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _sessionJson(String accessToken, String refreshToken) =>
      jsonEncode({
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'token_type': 'bearer',
        'expires_in': 3600,
      });

  /// Clear all tenant data on logout.
  Future<void> clearTenant() async {
    try {
      await _tenantClient?.auth.signOut();
    } catch (_) {}
    _tenantClient = null;
    _currentStation = null;
    await _storage.delete(key: StorageKeys.userSession);
    // Keep station code so user doesn't have to re-enter
  }

  /// Full reset - clear everything including station code.
  Future<void> fullReset() async {
    await clearTenant();
    await _storage.deleteAll();
  }
}
