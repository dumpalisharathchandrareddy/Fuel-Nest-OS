library;

/// App-wide constants matching existing web app standards

class AppConstants {
  AppConstants._();

  // ── App Identity ──────────────────────────────────────────────────────────
  static const appName = 'FuelOS';
  static const appTagline = 'Fuel Station Management, Simplified';
  static const appVersion = '1.0.0';

  // ── Registry (PUMPora central - baked into app build) ────────────────────
  // This is YOUR Supabase project URL - the central station registry
  // Each dealer looks up their own Supabase via their station code from here
  static const registrySupabaseUrl = String.fromEnvironment('REGISTRY_URL');
  static const registryAnonKey = String.fromEnvironment('REGISTRY_ANON_KEY');
  static bool get hasRegistry =>
      registrySupabaseUrl.isNotEmpty && registryAnonKey.isNotEmpty;

  // ── India Time ───────────────────────────────────────────────────────────
  static const defaultTimezone = 'Asia/Kolkata';

  // ── Pagination ────────────────────────────────────────────────────────────
  static const defaultPageSize = 20;
  static const reportPageSize = 50;

  // ── Cache duration ────────────────────────────────────────────────────────
  static const dashboardCacheMinutes = 5;
  static const staffListCacheMinutes = 30;
}

class FuelTypes {
  FuelTypes._();
  static const all = ['Petrol', 'Diesel', 'Power', 'CNG', 'LNG'];
}

class PaymentProviders {
  PaymentProviders._();
  static const all = [
    'Cash',
    'Paytm',
    'PhonePe',
    'GPay',
    'Razorpay',
    'Company Card',
    'UPI',
    'Card',
  ];
}

class UserRoles {
  UserRoles._();
  static const dealer = 'DEALER';
  static const manager = 'MANAGER';
  static const pumpPerson = 'PUMP_PERSON';

  static String displayName(String role) => switch (role) {
        'DEALER' => 'Dealer',
        'MANAGER' => 'Manager',
        'PUMP_PERSON' => 'Staff',
        _ => role,
      };
}

class ShiftStatus {
  ShiftStatus._();
  static const open = 'OPEN';
  static const closed = 'CLOSED';
  static const settled = 'SETTLED';
}

class StorageKeys {
  StorageKeys._();
  // Secure storage
  static const stationCode = 'station_code';
  static const tenantUrl = 'tenant_supabase_url';
  static const tenantAnonKey = 'tenant_anon_key';
  static const userSession = 'user_session';
  static const googleDriveToken = 'google_drive_token';
  // SharedPreferences
  static const cachedStationName = 'cached_station_name';
  static const cachedDashboard = 'cached_dashboard';
  static const cachedStaffList = 'cached_staff_list';
  static const discordWebhookUrl = 'discord_discord_webhook_url';
}
