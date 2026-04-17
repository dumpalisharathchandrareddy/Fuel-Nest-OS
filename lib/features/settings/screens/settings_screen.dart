import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/services/discord_service.dart';
import '../../../core/services/google_drive_service.dart';
import '../../../shared/widgets/widgets.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _discordCtrl = TextEditingController();
  bool _discordEnabled = true;
  bool _savingDiscord = false;
  bool _testingDiscord = false;
  bool _loadingDrive = false;
  bool _backingUp = false;
  String? _backupUrl;
  String? _driveEmail;
  bool _loadingSettings = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _discordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loadingSettings = true);
    try {
      // Load Discord from DB
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final config = await db
          .from('WebhookConfig')
          .select('url, enabled')
          .eq('station_id', user.stationId)
          .maybeSingle();
      if (config != null) {
        _discordCtrl.text = config['url'] as String? ?? '';
        _discordEnabled = config['enabled'] as bool? ?? true;
      }
      await DiscordService.instance.loadConfig();
      await GoogleDriveService.instance.restoreSignIn();
      setState(() {
        _driveEmail = GoogleDriveService.instance.signedInEmail;
        _loadingSettings = false;
      });
    } catch (e) {
      setState(() => _loadingSettings = false);
    }
  }

  Future<void> _saveDiscord() async {
    setState(() => _savingDiscord = true);
    try {
      await DiscordService.instance.saveConfig(
          webhookUrl: _discordCtrl.text.trim(), enabled: _discordEnabled);
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      if (_discordCtrl.text.trim().isNotEmpty) {
        await db.from('WebhookConfig').upsert({
          'station_id': user
              .stationId, // WebhookConfig has no provider field - one config per station
          'url': _discordCtrl.text.trim(), 'enabled': _discordEnabled,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'station_id');
      }
      if (mounted) _snack('✅ Saved', AppColors.green);
    } catch (e) {
      if (mounted) _snack('Error: $e', AppColors.red);
    } finally {
      if (mounted) setState(() => _savingDiscord = false);
    }
  }

  Future<void> _testDiscord() async {
    if (!DiscordService.instance.isConfigured) {
      _snack('Enter webhook URL first', AppColors.amber);
      return;
    }
    setState(() => _testingDiscord = true);
    final ok = await DiscordService.instance
        .sendTest(stationName: ref.read(stationNameProvider));
    if (mounted) {
      _snack(ok ? '✅ Test sent! Check Discord.' : '❌ Failed — check URL',
          ok ? AppColors.green : AppColors.red);
      setState(() => _testingDiscord = false);
    }
  }

  Future<void> _connectDrive() async {
    setState(() => _loadingDrive = true);
    try {
      final ok = await GoogleDriveService.instance.signIn();
      if (mounted) {
        if (ok) {
          setState(
              () => _driveEmail = GoogleDriveService.instance.signedInEmail);
          _snack('✅ Connected!', AppColors.green);
        } else {
          _snack('Cancelled', AppColors.amber);
        }
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', AppColors.red);
    } finally {
      if (mounted) setState(() => _loadingDrive = false);
    }
  }

  Future<void> _disconnectDrive() async {
    final ok = await showConfirmDialog(context,
        title: 'Disconnect Drive',
        message: 'You can reconnect anytime. Existing backups are kept.');
    if (!ok) return;
    await GoogleDriveService.instance.signOut();
    setState(() => _driveEmail = null);
  }

  Future<void> _runBackup() async {
    if (!GoogleDriveService.instance.isSignedIn) {
      _snack('Connect Google Drive first', AppColors.amber);
      return;
    }
    setState(() {
      _backingUp = true;
      _backupUrl = null;
    });
    try {
      final stationCode = ref.read(authProvider).stationCode ?? 'UNKNOWN';
      final url = await GoogleDriveService.instance.backupToGoogleDrive(
          stationName: ref.read(stationNameProvider), stationCode: stationCode);
      if (mounted) {
        setState(() {
          _backupUrl = url;
          _backingUp = false;
        });
        _snack('✅ Backup complete', AppColors.green);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _backingUp = false);
        _snack('Failed: $e', AppColors.red);
      }
    }
  }

  void _snack(String m, Color? bg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: bg));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isDealer = user?.isDealer ?? false;
    final stationName = ref.watch(stationNameProvider);
    final stationCode = ref.watch(authProvider).stationCode ?? '';

    if (_loadingSettings) {
      return const Scaffold(
          backgroundColor: AppColors.bgApp, body: LoadingView());
    }

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: RefreshIndicator(
          onRefresh: _loadSettings,
          color: AppColors.blue,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            // Station
            _Section(title: 'Station', children: [
              _Row('Name', stationName),
              _Row('Code', stationCode),
              _Row('Logged in as', user?.fullName ?? ''),
              _Row('Role', user?.displayRole ?? ''),
            ]),
            const SizedBox(height: 16),

            // Discord
            _Section(
                title: 'Discord Alerts',
                icon: Icons.notifications_outlined,
                children: [
                  Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.blueBg,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text(
                          'Alerts for shift closings, fuel deliveries, payroll, low stock.',
                          style: TextStyle(
                              color: AppColors.blue,
                              fontSize: 12,
                              height: 1.4))),
                  const SizedBox(height: 12),
                  if (!isDealer)
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.amberBg,
                            borderRadius: BorderRadius.circular(8)),
                        child: const Row(children: [
                          Icon(Icons.lock_outline,
                              color: AppColors.amber, size: 14),
                          SizedBox(width: 6),
                          Expanded(
                              child: Text('Only Dealer can configure Discord',
                                  style: TextStyle(
                                      color: AppColors.amber, fontSize: 12)))
                        ]))
                  else ...[
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Enable',
                              style: TextStyle(color: AppColors.textPrimary)),
                          Switch(
                              value: _discordEnabled,
                              onChanged: (v) =>
                                  setState(() => _discordEnabled = v)),
                        ]),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _discordCtrl,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Webhook URL',
                        hintText: 'https://discord.com/api/webhooks/...',
                        hintStyle: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: AppColors.bgCard,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: AppButton(
                              label: 'Save',
                              secondary: true,
                              loading: _savingDiscord,
                              onTap: _saveDiscord)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: AppButton(
                              label: 'Test',
                              loading: _testingDiscord,
                              onTap: _testDiscord)),
                    ]),
                  ],
                ]),
            const SizedBox(height: 16),

            // Google Drive
            if (isDealer) ...[
              _Section(
                  title: 'Google Drive Backup',
                  icon: Icons.backup_outlined,
                  children: [
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.greenBg,
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text(
                            'Full JSON backup of all data uploaded to your personal Google Drive.',
                            style: TextStyle(
                                color: AppColors.green,
                                fontSize: 12,
                                height: 1.4))),
                    const SizedBox(height: 12),
                    if (_driveEmail != null) ...[
                      Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppColors.bgCard,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color:
                                      AppColors.green.withOpacity(0.3))),
                          child: Row(children: [
                            const Icon(Icons.check_circle,
                                color: AppColors.green, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  const Text('Connected',
                                      style: TextStyle(
                                          color: AppColors.green,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  Text(_driveEmail!,
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 11)),
                                ])),
                            TextButton(
                                onPressed: _disconnectDrive,
                                child: const Text('Disconnect',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12))),
                          ])),
                      const SizedBox(height: 10),
                      if (_backupUrl != null)
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                                color: AppColors.green.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColors.green
                                        .withOpacity(0.3))),
                            child: Row(children: [
                              const Icon(Icons.cloud_done_outlined,
                                  color: AppColors.green, size: 14),
                              const SizedBox(width: 6),
                              const Expanded(
                                  child: Text('Backup uploaded to Drive',
                                      style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12))),
                              GestureDetector(
                                  onTap: () {
                                    Clipboard.setData(
                                        ClipboardData(text: _backupUrl!));
                                    _snack('Link copied', null);
                                  },
                                  child: const Icon(Icons.copy_outlined,
                                      size: 14, color: AppColors.textMuted)),
                            ])),
                      const SizedBox(height: 10),
                      AppButton(
                          label: 'Backup Now',
                          icon: Icons.backup,
                          loading: _backingUp,
                          width: double.infinity,
                          onTap: _runBackup),
                    ] else
                      AppButton(
                          label: 'Connect Google Drive',
                          icon: Icons.add_link,
                          loading: _loadingDrive,
                          width: double.infinity,
                          onTap: _connectDrive),
                  ]),
              const SizedBox(height: 16),
            ],

            // App
            const _Section(title: 'App Info', children: [
              _Row('App', AppConstants.appName),
              _Row('Version', AppConstants.appVersion),
              _Row('Timezone', 'Asia/Kolkata (IST)'),
              _Row('Storage', 'Your own Supabase'),
            ]),
            const SizedBox(height: 16),

            // Connection (Dealer only)
            if (isDealer) ...[
              _Section(title: 'Connection Settings', children: [
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AppColors.redBg,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text(
                        'CRITICAL: These settings link the app to your specific station database. Only modify if advised.',
                        style: TextStyle(
                            color: AppColors.red, fontSize: 11, height: 1.4))),
                const SizedBox(height: 12),
                _Row(
                    'Station URL',
                    TenantService.instance.currentStation?.supabaseUrl ??
                        'Not set'),
                const SizedBox(height: 4),
                _Row(
                    'Station Key',
                    TenantService.instance.currentStation?.anonKey != null
                        ? '••••••••'
                        : 'Not set'),
                const SizedBox(height: 8),
                const Text('Station ID (DB)',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
                Text(user?.stationId ?? 'Unknown',
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontFamily: 'monospace')),
              ]),
              const SizedBox(height: 16),
            ],

            // Logout
            AppButton(
                label: 'Logout',
                danger: true,
                width: double.infinity,
                onTap: () async {
                  final ok = await showConfirmDialog(context,
                      title: 'Logout',
                      message:
                          'Sign out from FuelOS. Station code is remembered.',
                      confirmLabel: 'Logout',
                      isDanger: true);
                  if (ok && mounted) {
                    await ref.read(authProvider.notifier).logout();
                  }
                }),
            if (isDealer) ...[
              const SizedBox(height: 8),
              AppButton(
                  label: 'Switch Station',
                  secondary: true,
                  width: double.infinity,
                  onTap: () async {
                    final ok = await showConfirmDialog(context,
                        title: 'Switch Station',
                        message:
                            'Clear session and return to station code screen.',
                        confirmLabel: 'Continue');
                    if (ok && mounted) {
                      ref.read(authProvider.notifier).clearStation();
                    }
                  }),
            ],
            const SizedBox(height: 32),
          ])),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final IconData? icon;
  const _Section({required this.title, required this.children, this.icon});
  @override
  Widget build(BuildContext context) => AppCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon!, size: 16, color: AppColors.blue),
            const SizedBox(width: 6)
          ],
          Text(title,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 10),
        ...children,
      ]));
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13))),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis)),
      ]));
}
