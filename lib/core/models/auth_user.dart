import 'dart:convert';

class AuthUser {
  final String id;
  final String stationId;
  final String stationCode;
  final String stationName;
  final String role;
  final String fullName;
  final String? employeeId;
  final String? phoneNumber;
  // Supabase session
  final String? accessToken;
  final String? refreshToken;

  const AuthUser({
    required this.id,
    required this.stationId,
    required this.stationCode,
    required this.stationName,
    required this.role,
    required this.fullName,
    this.employeeId,
    this.phoneNumber,
    this.accessToken,
    this.refreshToken,
  });

  bool get isDealer => role == 'DEALER';
  bool get isManager => role == 'MANAGER';
  bool get isStaff => role == 'PUMP_PERSON';
  bool get isManagerOrDealer => isDealer || isManager;

  String get displayRole => switch (role) {
    'DEALER' => 'Dealer',
    'MANAGER' => 'Manager',
    'PUMP_PERSON' => 'Staff',
    _ => role,
  };

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    stationId: json['station_id'] as String,
    stationCode: json['station_code'] as String? ?? '',
    stationName: json['station_name'] as String? ?? '',
    role: json['role'] as String,
    fullName: json['full_name'] as String,
    employeeId: json['employee_id'] as String?,
    phoneNumber: json['phone_number'] as String?,
    accessToken: json['access_token'] as String?,
    refreshToken: json['refresh_token'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'station_id': stationId,
    'station_code': stationCode,
    'station_name': stationName,
    'role': role,
    'full_name': fullName,
    'employee_id': employeeId,
    'phone_number': phoneNumber,
    'access_token': accessToken,
    'refresh_token': refreshToken,
  };

  String toJsonString() => jsonEncode(toJson());

  static AuthUser? fromJsonString(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return AuthUser.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  AuthUser copyWith({
    String? accessToken,
    String? refreshToken,
  }) => AuthUser(
    id: id,
    stationId: stationId,
    stationCode: stationCode,
    stationName: stationName,
    role: role,
    fullName: fullName,
    employeeId: employeeId,
    phoneNumber: phoneNumber,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
  );
}

/// Station registry entry from PUMPora's central Supabase
class StationRegistryEntry {
  final String stationCode;
  final String stationName;
  final String supabaseUrl;
  final String anonKey;

  const StationRegistryEntry({
    required this.stationCode,
    required this.stationName,
    required this.supabaseUrl,
    required this.anonKey,
  });

  factory StationRegistryEntry.fromJson(Map<String, dynamic> json) =>
      StationRegistryEntry(
        stationCode: json['station_code'] as String,
        stationName: json['station_name'] as String,
        supabaseUrl: json['supabase_url'] as String,
        anonKey: json['anon_key'] as String,
      );
}
