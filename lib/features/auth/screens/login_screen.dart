// ─── role_select_screen.dart ──────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/widgets/widgets.dart';

class RoleSelectScreen extends ConsumerWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? size.width * 0.25 : 24,
              vertical: 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back + station info
                GestureDetector(
                  onTap: () {
                    ref.read(authProvider.notifier).clearStation();
                    context.go('/station');
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_ios,
                          size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        auth.stationCode ?? '',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  auth.stationName ?? 'Select Role',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose how you want to sign in',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 32),

                _RoleCard(
                  title: 'Dealer',
                  subtitle: 'Full access — settings, reports, all data',
                  icon: Icons.admin_panel_settings_outlined,
                  color: AppColors.amber,
                  onTap: () => context.go('/login/dealer'),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  title: 'Manager',
                  subtitle: 'Daily operations — shifts, payroll, inventory',
                  icon: Icons.manage_accounts_outlined,
                  color: AppColors.blue,
                  onTap: () => context.go('/login/manager'),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  title: 'Staff',
                  subtitle: 'Pump entry — nozzle readings, shift execution',
                  icon: Icons.local_gas_station_outlined,
                  color: AppColors.green,
                  onTap: () => context.go('/login/staff'),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  title: 'Credit Customer',
                  subtitle: 'Check your credit balance and transactions',
                  icon: Icons.credit_card_outlined,
                  color: AppColors.purple,
                  onTap: () => context.go('/creditor'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              color: AppColors.textMuted, size: 20),
        ],
      ),
    );
  }
}

// ─── login_screen.dart ────────────────────────────────────────────────────────

class LoginScreen extends ConsumerStatefulWidget {
  final String role;
  const LoginScreen({super.key, required this.role});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _credentialCtrl = TextEditingController();
  bool _usePin = false;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _credentialCtrl.dispose();
    super.dispose();
  }

  String get _title => switch (widget.role) {
    'DEALER' => 'Dealer Login',
    'MANAGER' => 'Manager Login',
    _ => 'Staff Login',
  };

  String get _identifierLabel => switch (widget.role) {
    'PUMP_PERSON' => 'Employee ID',
    _ => 'Username',
  };

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await ref.read(authProvider.notifier).login(
      identifier: _identifierCtrl.text.trim(),
      credential: _credentialCtrl.text.trim(),
      role: widget.role,
      isPin: _usePin,
    );

    if (success && mounted) {
      final user = ref.read(authProvider).user!;
      if (user.role == 'PUMP_PERSON') {
        context.go('/worker');
      } else {
        context.go('/app/dashboard');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    final color = switch (widget.role) {
      'DEALER' => AppColors.amber,
      'MANAGER' => AppColors.blue,
      _ => AppColors.green,
    };

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? size.width * 0.28 : 24,
              vertical: 32,
            ),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back
                  GestureDetector(
                    onTap: () => context.go('/login'),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_ios,
                            size: 14, color: AppColors.textMuted),
                        SizedBox(width: 4),
                        Text('Back',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Role icon
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.person_outline, color: color, size: 26),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    _title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    auth.stationName ?? '',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  // Identifier
                  AppTextField(
                    label: _identifierLabel,
                    hint: widget.role == 'PUMP_PERSON'
                        ? 'Your employee ID'
                        : 'Your username',
                    controller: _identifierCtrl,
                    prefixIcon: Icons.person_outline,
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Toggle PIN / Password
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Sign in with',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _usePin = !_usePin),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _usePin ? 'Password' : 'PIN',
                              style: const TextStyle(
                                  color: AppColors.blue, fontSize: 12),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.swap_horiz,
                                size: 14, color: AppColors.blue),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AppTextField(
                    label: _usePin ? 'PIN' : 'Password',
                    hint: _usePin ? '4–6 digit PIN' : 'Your password',
                    controller: _credentialCtrl,
                    obscure: true,
                    keyboardType: _usePin
                        ? TextInputType.number
                        : TextInputType.visiblePassword,
                    prefixIcon:
                        _usePin ? Icons.pin_outlined : Icons.lock_outline,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
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
                    label: 'Sign In',
                    onTap: _login,
                    loading: auth.isLoading,
                    width: double.infinity,
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
