import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/widgets/widgets.dart';

class StationCodeScreen extends ConsumerStatefulWidget {
  const StationCodeScreen({super.key});

  @override
  ConsumerState<StationCodeScreen> createState() => _StationCodeScreenState();
}

class _StationCodeScreenState extends ConsumerState<StationCodeScreen> {
  final _ctrl = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _proceed() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    await ref
        .read(authProvider.notifier)
        .configureStation(_ctrl.text.trim().toUpperCase());

    if (!mounted) return;
    final auth = ref.read(authProvider);
    if (auth.error == null && auth.stationConfigured) {
      context.go('/login');
    }
  }

  void _showManualConfig() {
    final urlCtrl = TextEditingController();
    final keyCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Manual Configuration',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter tenant database credentials directly.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Supabase URL',
                labelStyle: TextStyle(color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Anon Key',
                labelStyle: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(authProvider.notifier).configureManual(
                    url: urlCtrl.text.trim(),
                    key: keyCtrl.text.trim(),
                  );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? size.width * 0.3 : 24,
              vertical: 32,
            ),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.blueBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.blue.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.local_gas_station,
                            color: AppColors.blue, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'FuelOS',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),

                  const Text(
                    'Enter Station Code',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Provide your station code to connect to your operational database.',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.5),
                  ),
                  const SizedBox(height: 32),

                  AppTextField(
                    label: 'Station Code',
                    hint: 'e.g. STATION001',
                    controller: _ctrl,
                    prefixIcon: Icons.store_outlined,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _proceed(),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter your station code';
                      }
                      return null;
                    },
                  ),

                  if (auth.error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.redBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              auth.error!,
                              style: const TextStyle(
                                  color: AppColors.red, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                  AppButton(
                    label: 'Connect to Station',
                    onTap: _proceed,
                    loading: auth.isLoading,
                    width: double.infinity,
                  ),

                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Try Demo Mode',
                    onTap: () =>
                        ref.read(authProvider.notifier).enterDemoMode(),
                    secondary: true,
                    width: double.infinity,
                  ),

                  const SizedBox(height: 40),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 32),

                  const Text(
                    'First time here?',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Register your station and setup your internal operational database.',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Register New Station',
                    onTap: () => context.go('/signup'),
                    secondary: true,
                    width: double.infinity,
                  ),

                  if (!AppConstants.hasRegistry) ...[
                    const SizedBox(height: 24),
                    const Center(
                      child: Text(
                        'Note: Central Registry is not configured in this build.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/creditor'),
                      child: const Text(
                        'Access Creditor Portal →',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed: _showManualConfig,
                      child: const Text(
                        'Dev: Manual Configuration',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
