library;

/// App-wide constants matching existing web app standards

class AppConstants {
  AppConstants._();

  // ── App Identity ──────────────────────────────────────────────────────────
  static const appName = 'FuelOS';
  static const appTagline = 'Fuel Station Management, Simplified';
  static const appVersion = '1.0.0';

  // ── Registry Supabase (FuelOS-owned central lookup project) ─────────────
  // Supabase project that maps station_code → dealer's Supabase URL.
  // Used only for station code lookup at login and station registration at signup.
  // Pass at build time:
  //   --dart-define=REGISTRY_URL=https://xxxx.supabase.co
  //   --dart-define=REGISTRY_ANON_KEY=eyJ...
  static const registrySupabaseUrl = String.fromEnvironment('REGISTRY_URL');
  static const registryAnonKey = String.fromEnvironment('REGISTRY_ANON_KEY');
  static bool get hasRegistry =>
      registrySupabaseUrl.isNotEmpty && registryAnonKey.isNotEmpty;

  // ── Managed Dealer Supabase (FuelOS-owned shared dealer data project) ───
  // Supabase project that hosts station data for dealers who chose "managed mode".
  // All managed dealers share this single Supabase project; stations are isolated
  // by station_id within it (RLS enforced).
  // BYO dealers use their own Supabase URL instead — this is never used for them.
  // Pass at build time:
  //   --dart-define=MANAGED_DEALER_URL=https://yyyy.supabase.co
  //   --dart-define=MANAGED_DEALER_ANON_KEY=eyJ...
  static const managedDealerUrl =
      String.fromEnvironment('MANAGED_DEALER_URL');
  static const managedDealerAnonKey =
      String.fromEnvironment('MANAGED_DEALER_ANON_KEY');
  static bool get hasManagedDealer =>
      managedDealerUrl.isNotEmpty && managedDealerAnonKey.isNotEmpty;

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
  static const stationName = 'station_name';
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
