import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/auth_user.dart';
import '../constants/app_constants.dart';
import 'tenant_service.dart';
import 'registry_service.dart';

/// Handles all authentication flows for all 4 hubs.
/// Dealer / Manager / Staff → station's own Supabase (via Edge Function login)
/// Creditor → station's own Supabase (read-only credit data)
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

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

  /// Step 2a: Login as Dealer or Manager or Staff.
  /// identifier = username or employee_id
  /// credential = password or PIN
  /// role = 'DEALER' | 'MANAGER' | 'PUMP_PERSON'
  Future<AuthUser> loginStaff({
    required String identifier,
    required String credential,
    required String role,
    bool isPin = false,
  }) async {
    final db = TenantService.instance.client;
    final stationCode =
        TenantService.instance.currentStation?.stationCode ?? '';

    // Call the Supabase Edge Function for auth
    // This Edge Function validates credentials and returns user data + session
    final response = await db.functions.invoke(
      'auth-login',
      body: {
        'identifier': identifier.trim(),
        'credential': credential,
        'role': role,
        'is_pin': isPin,
        'station_code': stationCode,
      },
    );

    if (response.status != 200) {
      final error = response.data?['error'] ?? 'Login failed';
      throw Exception(error.toString());
    }

    final data = response.data as Map<String, dynamic>;
    final user = AuthUser.fromJson({
      ...data['user'] as Map<String, dynamic>,
      'station_code': stationCode,
      'station_name': TenantService.instance.currentStation?.stationName ?? '',
      'access_token': data['access_token'],
      'refresh_token': data['refresh_token'],
    });

    // Set Supabase session so RLS works for subsequent calls
    if (data['access_token'] != null && data['refresh_token'] != null) {
      await TenantService.instance.setSession(
        data['access_token'] as String,
        data['refresh_token'] as String,
      );
    }

    _currentUser = user;
    await _persistUser(user);
    return user;
  }

  /// Step 2b: Creditor login - just validates phone number, no Supabase Auth needed
  /// Returns credit summary for the phone number at that station
  Future<Map<String, dynamic>> loginCreditor({
    required String phoneNumber,
  }) async {
    final db = TenantService.instance.client;

    // Creditors use anon access - RLS policy allows reading own credit data by phone
    final data = await db
        .from('CreditCustomer')
        .select('id, name, customer_code, phone_number, advance_balance')
        .eq('phone_number', phoneNumber.trim())
        .eq('active', true)
        .maybeSingle();

    if (data == null) {
      throw Exception(
        'No credit account found for this phone number at this station.',
      );
    }

    return data;
  }

  /// Restore session on app launch
  Future<AuthUser?> restoreSession() async {
    // Try to restore tenant connection
    final stationCode = await TenantService.instance.restoreFromStorage();
    if (stationCode == null) return null;

    // Restore user from secure storage
    final userJson =
        await _storage.read(key: StorageKeys.userSession + '_user');
    if (userJson == null) return null;

    final user = AuthUser.fromJsonString(userJson);
    if (user == null) return null;

    // Try to restore Supabase session
    await TenantService.instance.restoreSession();

    _currentUser = user;
    return user;
  }

  /// Logout current user
  Future<void> logout() async {
    _currentUser = null;
    await TenantService.instance.clearTenant();
    await _storage.delete(key: StorageKeys.userSession + '_user');
  }

  Future<void> _persistUser(AuthUser user) async {
    await _storage.write(
      key: StorageKeys.userSession + '_user',
      value: user.toJsonString(),
    );
  }
}

/// Dealer onboarding service - sets up a new dealer's Supabase project
class DealerSetupService {
  DealerSetupService._();
  static final instance = DealerSetupService._();

  /// Register a new dealer station.
  /// Called during first-time dealer signup.
  Future<AuthUser> signupDealer({
    required String stationCode,
    required String stationName,
    required String ownerName,
    required String phone,
    required String password,
    required String supabaseUrl,
    required String anonKey,
    // Optional additional station details
    String? address,
    String? city,
    String? state,
  }) async {
    // 1. Configure tenant with provided Supabase credentials
    final entry = StationRegistryEntry(
      stationCode: stationCode.trim().toUpperCase(),
      stationName: stationName.trim(),
      supabaseUrl: supabaseUrl.trim(),
      anonKey: anonKey.trim(),
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

    if (response.status != 200) {
      throw Exception(response.data?['error'] ?? 'Signup failed');
    }

    final data = response.data as Map<String, dynamic>;

    // 3. Register in central PUMPora registry
    await RegistryService.instance.registerStation(
      stationCode: stationCode.trim().toUpperCase(),
      stationName: stationName.trim(),
      supabaseUrl: supabaseUrl.trim(),
      anonKey: anonKey.trim(),
    );

    // 4. Return authenticated user
    final user = AuthUser.fromJson({
      ...data['user'] as Map<String, dynamic>,
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

    return user;
  }
}
