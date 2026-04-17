import 'package:flutter/foundation.dart';
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
    if (!AppConstants.hasRegistry) {
      throw Exception('Registry not configured. Please provide REGISTRY_URL and REGISTRY_ANON_KEY.');
    }
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
  /// Calls the register-station Edge Function deployed to the central registry
  /// project (manuhbjwasbpbuggkhgq). The function uses service role server-side
  /// to bypass RLS — the anon key cannot INSERT into station_registry directly.
  Future<void> registerStation({
    required String stationCode,
    required String stationName,
    required String supabaseUrl,
    required String anonKey,
  }) async {
    try {
      final response = await _registry.functions.invoke(
        'register-station',
        body: {
          'station_code': stationCode.trim().toUpperCase(),
          'station_name': stationName.trim(),
          'supabase_url': supabaseUrl.trim(),
          'anon_key': anonKey.trim(),
        },
      );
      final raw = response.data;
      debugPrint('register-station response.data=${raw.toString()} type=${raw.runtimeType}');
      if (raw == null) {
        throw Exception('Registry function returned empty response');
      }
      if (raw is! Map) {
        throw Exception(
          'Unexpected registry response type: ${raw.runtimeType}',
        );
      }
      final data = Map<String, dynamic>.from(raw);
      if (data['success'] != true) {
        throw Exception(
          'Failed to register station: ${data['error'] ?? 'unknown error'}',
        );
      }
    } on FunctionException catch (e) {
      final detail = e.details?.toString() ?? e.toString();
      throw Exception('Failed to register station: $detail');
    }
  }

  /// Verify a station code exists without returning sensitive data.
  Future<bool> stationExists(String stationCode) async {
    final result = await lookupStation(stationCode);
    return result != null;
  }
}
