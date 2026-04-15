import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
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
                              color: AppColors.blue.withOpacity(0.3)),
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
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your station code is provided by your dealer. It identifies which fuel station you belong to.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14,
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
                      if (v.trim().length < 4) {
                        return 'Station code must be at least 4 characters';
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
                            color: AppColors.red.withOpacity(0.3)),
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
                    label: 'Continue',
                    onTap: _proceed,
                    loading: auth.isLoading,
                    width: double.infinity,
                  ),

                  const SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/signup'),
                      child: const Text(
                        'New dealer? Register your station →',
                        style: TextStyle(
                            color: AppColors.blue, fontSize: 13),
                      ),
                    ),
                  ),

                  // Creditor link
                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/creditor'),
                      child: const Text(
                        'Check your credit account',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12),
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
