import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import '../models/auth_user.dart';

/// Connects to PUMPora's central registry Supabase.
/// Used ONLY for station_code → Supabase URL lookups.
/// Manager/Staff never interact with this directly.
class RegistryService {
  RegistryService._();
  static final instance = RegistryService._();

  SupabaseClient? _client;

  SupabaseClient get _registry {
    _client ??= SupabaseClient(
      AppConstants.registrySupabaseUrl,
      AppConstants.registryAnonKey,
    );
    return _client!;
  }

  /// Look up a station code in the central registry.
  /// Returns null if not found.
  Future<StationRegistryEntry?> lookupStation(String stationCode) async {
    try {
      final data = await _registry
          .from('station_registry')
          .select('station_code, station_name, supabase_url, anon_key')
          .eq('station_code', stationCode.trim().toUpperCase())
          .eq('active', true)
          .maybeSingle();

      if (data == null) return null;
      return StationRegistryEntry.fromJson(data);
    } on PostgrestException catch (e) {
      throw Exception('Registry lookup failed: ${e.message}');
    }
  }

  /// Register a new dealer station in the central registry.
  /// Called during dealer signup flow.
  Future<void> registerStation({
    required String stationCode,
    required String stationName,
    required String supabaseUrl,
    required String anonKey,
  }) async {
    try {
      await _registry.from('station_registry').upsert({
        'station_code': stationCode.trim().toUpperCase(),
        'station_name': stationName.trim(),
        'supabase_url': supabaseUrl.trim(),
        'anon_key': anonKey.trim(),
        'active': true,
        'registered_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on PostgrestException catch (e) {
      throw Exception('Failed to register station: ${e.message}');
    }
  }

  /// Verify a station code exists without returning sensitive data.
  Future<bool> stationExists(String stationCode) async {
    final result = await lookupStation(stationCode);
    return result != null;
  }
}
