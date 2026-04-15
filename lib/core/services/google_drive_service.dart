import 'dart:convert';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'discord_service.dart';
import 'tenant_service.dart';
import '../utils/ist_time.dart';

/// Google Drive backup service.
/// Dealer signs in once with Google OAuth (in-app).
/// All backups go to a 'FuelOS Backups' folder in their Drive.
class GoogleDriveService {
  GoogleDriveService._();
  static final instance = GoogleDriveService._();

  static final _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  GoogleSignInAccount? _account;
  String? _backupFolderId;

  bool get isSignedIn => _account != null;
  String? get signedInEmail => _account?.email;

  /// Trigger Google sign-in (shows consent screen).
  /// Call this from the Settings screen (dealer only).
  Future<bool> signIn() async {
    try {
      _account = await _googleSignIn.signIn();
      if (_account != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('google_drive_email', _account!.email);
        // Create backup folder
        await _ensureBackupFolder();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Sign out from Google Drive
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _account = null;
    _backupFolderId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('google_drive_email');
    await prefs.remove('google_drive_folder_id');
  }

  /// Restore sign-in state on app launch
  Future<void> restoreSignIn() async {
    try {
      _account = await _googleSignIn.signInSilently();
      if (_account != null) {
        final prefs = await SharedPreferences.getInstance();
        _backupFolderId = prefs.getString('google_drive_folder_id');
      }
    } catch (_) {}
  }

  /// Backup entire station data to Google Drive as JSON.
  /// Returns the Drive file URL.
  Future<String?> backupToGoogleDrive({
    required String stationName,
    required String stationCode,
  }) async {
    if (!isSignedIn) throw Exception('Not signed in to Google Drive');

    final driveApi = await _getDriveApi();
    if (driveApi == null) throw Exception('Failed to connect to Google Drive');

    final folderId = await _ensureBackupFolder();

    // Fetch all data from Supabase
    final db = TenantService.instance.client;
    final now = IstTime.formatDateTime(DateTime.now().toUtc());
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Collect data
    final backup = <String, dynamic>{
      'exported_at': now,
      'station_code': stationCode,
      'station_name': stationName,
      'version': '1.0',
    };

    // Fetch key tables
    final tables = [
      'Shift', 'NozzleEntry', 'PaymentRecord', 'FuelRate',
      'Tank', 'Pump', 'Nozzle', 'FuelOrder', 'InventoryCheque',
      'CreditCustomer', 'CreditTransaction', 'CreditPayment',
      'SalaryPayout', 'StaffAdvance', 'DailyExpense',
    ];

    for (final table in tables) {
      try {
        final data = await db.from(table).select();
        backup[table] = data;
      } catch (_) {
        backup[table] = [];
      }
    }

    // Write to temp file
    final tempDir = await getTemporaryDirectory();
    final filename =
        'fuelos_backup_${stationCode}_$timestamp.json';
    final file = File('${tempDir.path}/$filename');
    await file.writeAsString(jsonEncode(backup));

    // Upload to Drive
    final fileMetadata = drive.File()
      ..name = filename
      ..parents = [folderId]
      ..mimeType = 'application/json';

    final response = await driveApi.files.create(
      fileMetadata,
      uploadMedia: drive.Media(file.openRead(), await file.length()),
    );

    final fileId = response.id;
    final fileUrl =
        'https://drive.google.com/file/d/$fileId/view';

    // Save folder ID
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('google_drive_folder_id', folderId);

    // Discord notification
    await DiscordService.instance.sendBackupComplete(
      fileName: filename,
      fileSizeKb: (await file.length()) ~/ 1024,
      driveLink: fileUrl,
    );

    // Cleanup temp file
    await file.delete();

    return fileUrl;
  }

  Future<String> _ensureBackupFolder() async {
    if (_backupFolderId != null) return _backupFolderId!;

    final driveApi = await _getDriveApi();
    if (driveApi == null) throw Exception('Drive API unavailable');

    // Search for existing folder
    final existing = await driveApi.files.list(
      q: "name='FuelOS Backups' and mimeType='application/vnd.google-apps.folder' and trashed=false",
      spaces: 'drive',
    );

    if (existing.files != null && existing.files!.isNotEmpty) {
      _backupFolderId = existing.files!.first.id;
      return _backupFolderId!;
    }

    // Create the folder
    final folder = drive.File()
      ..name = 'FuelOS Backups'
      ..mimeType = 'application/vnd.google-apps.folder';

    final created = await driveApi.files.create(folder);
    _backupFolderId = created.id!;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('google_drive_folder_id', _backupFolderId!);

    return _backupFolderId!;
  }

  Future<drive.DriveApi?> _getDriveApi() async {
    if (_account == null) return null;
    final httpClient = await _googleSignIn.authenticatedClient();
    if (httpClient == null) return null;
    return drive.DriveApi(httpClient);
  }
}
