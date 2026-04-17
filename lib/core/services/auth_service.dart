import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/auth_user.dart';
import '../constants/app_constants.dart';
import 'tenant_service.dart';
import 'registry_service.dart';

/// Safely parses a Supabase [FunctionResponse.data] value.
/// Throws a clear [Exception] if the data is null or not a Map.
/// The Supabase Flutter SDK can return null even on 2xx when the response
/// body is empty or the content-type is unexpected.
Map<String, dynamic> _parseData(dynamic raw, {required String context}) {
  if (raw == null) {
    throw Exception('$context: empty response body');
  }
  if (raw is! Map) {
    throw Exception('$context: unexpected response type ${raw.runtimeType}');
  }
  return Map<String, dynamic>.from(raw);
}

/// Extracts a readable error string from a raw response body.
/// Falls back to [fallback] when nothing useful can be extracted.
String _errorFrom(dynamic raw, {required String fallback}) {
  if (raw == null) return fallback;
  if (raw is Map) return (raw['error'] ?? raw['message'] ?? fallback).toString();
  return fallback;
}

/// Handles all authentication flows for all 4 hubs.
/// Dealer / Manager / Staff → station's own Supabase (via Edge Function login)
/// Creditor → station's own Supabase (read-only credit data)
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Defensive Storage Helpers ─────────────────────────────────────────────
  
  Future<String?> _read(String key) async {
    try {
      debugPrint('[AUTH] 🔍 Reading key: $key...');
      final value = await _storage.read(key: key).timeout(const Duration(seconds: 15));
      debugPrint('[AUTH] ✅ Read $key: ${value != null ? "FOUND" : "NOT FOUND"}');
      return value;
    } catch (e) {
      debugPrint('[AUTH] ❌ AuthService error reading key $key: $e');
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      debugPrint('[AUTH] 💾 Writing key: $key...');
      await _storage.write(key: key, value: value).timeout(const Duration(seconds: 15));
      debugPrint('[AUTH] ✅ Written $key');
    } catch (e) {
      debugPrint('[AUTH] ❌ AuthService error writing key $key: $e');
    }
  }

  Future<void> _delete(String key) async {
    try {
      debugPrint('[AUTH] 🗑️ Deleting key: $key...');
      await _storage.delete(key: key).timeout(const Duration(seconds: 15));
      debugPrint('[AUTH] ✅ Deleted $key');
    } catch (e) {
      debugPrint('[AUTH] ❌ AuthService error deleting key $key: $e');
    }
  }

  AuthUser? _currentUser;
  AuthUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// Step 1: Look up station code → configure tenant Supabase client.
  /// Returns station name if found.
  Future<String> configureStation(String stationCode) async {
    final entry = await RegistryService.instance.lookupStation(stationCode);
    if (entry == null) {
      throw Exception(
        'Station code "$stationCode" not found. '
        'Please check with your dealer.',
      );
    }
    await TenantService.instance.configure(entry);
    return entry.stationName;
  }

  /// Step 2a: Unified login for all roles using Phone Number + PIN/Password.
  /// identifier = phone number
  /// credential = password or PIN
  /// role = DEALER | MANAGER | STAFF | PUMP_PERSON
  Future<AuthUser> loginUnified({
    required String identifier,
    required String credential,
    required String role,
    bool isPin = false,
  }) async {
    final curStation = TenantService.instance.currentStation;
    final stationCode = curStation?.stationCode ?? '';

    // Demo Mode: only fires for the DEMO001 station code
    if (stationCode == 'DEMO001') {
      return AuthUser(
        id: 'demo-user-id',
        stationId: 'demo-station-id',
        stationCode: 'DEMO001',
        stationName: curStation?.stationName ?? 'FuelOS Demo Station',
        role: 'MANAGER',
        fullName: 'Demo Manager',
      );
    }

    final db = TenantService.instance.client;

    try {
      // Call the Supabase Edge Function for auth
      final response = await db.functions.invoke(
        'auth-login',
        body: {
          'identifier': identifier.trim(),
          'credential': credential,
          'station_code': stationCode,
          'role': role,
          'is_pin': isPin,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.status != 200) {
        throw Exception(_errorFrom(response.data, fallback: 'Login failed'));
      }

      final data = _parseData(response.data, context: 'auth-login');
      final userRaw = data['user'];
      if (userRaw == null || userRaw is! Map) {
        throw Exception('auth-login: missing user in response');
      }
      final user = AuthUser.fromJson({
        ...Map<String, dynamic>.from(userRaw),
        'station_code': stationCode,
        'station_name': curStation?.stationName ?? '',
        'access_token': data['access_token'],
        'refresh_token': data['refresh_token'],
      });

      if (data['access_token'] != null && data['refresh_token'] != null) {
        await TenantService.instance.setSession(
          data['access_token'] as String,
          data['refresh_token'] as String,
        );
      }

      _currentUser = user;
      await _persistUser(user);
      return user;
    } catch (e) {
      // Dev-only fallback when Edge Function is unavailable locally
      if (kDebugMode && identifier == 'demo' && credential == 'demo') {
        return AuthUser(
          id: 'dev-user-id',
          stationId: 'dev-station-id',
          stationCode: stationCode,
          stationName: curStation?.stationName ?? 'Dev Station',
          role: role,
          fullName: 'Dev User',
        );
      }
      rethrow;
    }
  }

  /// Restore session on app launch
  Future<AuthUser?> restoreSession() async {
    debugPrint('[AUTH] 🔄 Beginning user session restoration...');
    // Stage 1: Check technical config
    if (!TenantService.instance.isConfigured) {
      debugPrint('[AUTH] ✋ Bailing: Technical tenant not configured.');
      return null;
    }

    // Stage 2: Restore user JSON from storage
    final key = '${StorageKeys.userSession}_user';
    final userJson = await _read(key);
    
    if (userJson == null) {
      debugPrint('[AUTH] ℹ️ No persisted user JSON found.');
      return null;
    }

    debugPrint('[AUTH] 📂 Found user JSON (len=${userJson.length}). Decoding...');
    final user = AuthUser.fromJsonString(userJson);
    if (user == null) {
      debugPrint('[AUTH] ❌ FAILED to decode user JSON.');
      await _delete(key); // Clear corrupt data
      return null;
    }

    // Stage 3: Sync Supabase tech session
    debugPrint('[AUTH] 🔗 App user ${user.fullName} found. Syncing Supabase tech session...');
    final syncOk = await TenantService.instance.restoreSession();

    if (!syncOk) {
      debugPrint('[AUTH] ⚠️ Supabase sync failed (expired/invalid). Clearing user persistence.');
      // Keep station config, but clear user-specific data
      _currentUser = null;
      await _delete(key);
      await TenantService.instance.clearUserSession();
      return null;
    }

    debugPrint('[AUTH] ✨ Restoration SUCCESS for ${user.fullName}');
    _currentUser = user;
    return user;
  }

  /// Logout current user
  Future<void> logout() async {
    _currentUser = null;
    await TenantService.instance.clearTenant();
    await _delete('${StorageKeys.userSession}_user');
  }

  Future<void> _persistUser(AuthUser user) async {
    await _write(
      '${StorageKeys.userSession}_user',
      user.toJsonString(),
    );
  }
}

/// Dealer onboarding service - sets up a new dealer's Supabase project
class DealerSetupService {
  DealerSetupService._();
  static final instance = DealerSetupService._();

  /// Register a new dealer station.
  /// Called during first-time dealer signup.
  ///
  /// [dbMode] is 'byo' (default) or 'managed'.
  /// For 'managed', [supabaseUrl] and [anonKey] are ignored.
  Future<AuthUser> signupDealer({
    required String stationCode,
    required String stationName,
    required String ownerName,
    required String phone,
    required String password,
    String supabaseUrl = '',
    String anonKey = '',
    String dbMode = 'byo',
    // Optional additional station details
    String? address,
    String? city,
    String? state,
  }) async {
    // Resolve which Supabase project to use.
    // managed → FuelOS-owned shared project (all managed dealers share one DB).
    // byo     → dealer's own Supabase project (URL/key provided by user).
    final String resolvedUrl;
    final String resolvedAnonKey;
    if (dbMode == 'managed') {
      if (!AppConstants.hasManagedDealer) {
        throw Exception(
          'Managed onboarding is not available in this build. '
          'Please use "Connect My Own Supabase" or contact FuelOS support.',
        );
      }
      resolvedUrl = AppConstants.managedDealerUrl;
      resolvedAnonKey = AppConstants.managedDealerAnonKey;
    } else {
      resolvedUrl = supabaseUrl.trim();
      resolvedAnonKey = anonKey.trim();
    }

    // 1. Configure tenant with the resolved Supabase credentials
    final entry = StationRegistryEntry(
      stationCode: stationCode.trim().toUpperCase(),
      stationName: stationName.trim(),
      supabaseUrl: resolvedUrl,
      anonKey: resolvedAnonKey,
    );
    await TenantService.instance.configure(entry);

    // 2. Call signup edge function in dealer's Supabase
    final db = TenantService.instance.client;
    final response = await db.functions.invoke(
      'auth-signup-dealer',
      body: {
        'station_code': stationCode.trim().toUpperCase(),
        'station_name': stationName.trim(),
        'owner_name': ownerName.trim(),
        'phone': phone.trim(),
        'password': password,
        'address_line_1': address,
        'city': city,
        'state': state,
      },
    );

    debugPrint('auth-signup-dealer response.data=${response.data.toString()} type=${response.data.runtimeType}');
    if (response.status != 200) {
      throw Exception(
        _errorFrom(response.data, fallback: 'Signup failed'),
      );
    }

    final data = _parseData(response.data, context: 'auth-signup-dealer');
    final userRaw = data['user'];
    if (userRaw == null || userRaw is! Map) {
      throw Exception('auth-signup-dealer: missing user in response');
    }

    // 3. Register in central registry (maps station_code → resolved Supabase project)
    await RegistryService.instance.registerStation(
      stationCode: stationCode.trim().toUpperCase(),
      stationName: stationName.trim(),
      supabaseUrl: resolvedUrl,
      anonKey: resolvedAnonKey,
    );

    // 4. Return authenticated user
    final user = AuthUser.fromJson({
      ...Map<String, dynamic>.from(userRaw),
      'station_code': stationCode,
      'station_name': stationName,
      'access_token': data['access_token'],
      'refresh_token': data['refresh_token'],
    });

    if (data['access_token'] != null && data['refresh_token'] != null) {
      await TenantService.instance.setSession(
        data['access_token'] as String,
        data['refresh_token'] as String,
      );
    }

    // Persist user so the app can restore session on next launch
    AuthService.instance._currentUser = user;
    await AuthService.instance._persistUser(user);

    return user;
  }
}
