import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/widgets/widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _credentialCtrl = TextEditingController();
  bool _usePin = true;
  String _role = 'PUMP_PERSON';

  static const _roles = [
    ('PUMP_PERSON', 'Staff'),
    ('MANAGER', 'Manager'),
    ('DEALER', 'Dealer'),
  ];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _credentialCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await ref.read(authProvider.notifier).login(
          identifier: _phoneCtrl.text.trim(),
          credential: _credentialCtrl.text.trim(),
          role: _role,
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
                  // Back to station code
                  GestureDetector(
                    onTap: () async {
                      await ref.read(authProvider.notifier).clearStation();
                      if (mounted) context.go('/station');
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back_ios,
                            size: 14, color: AppColors.textMuted),
                        SizedBox(width: 4),
                        Text('Switch Station',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // App Logo/Icon
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.blueBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.login_rounded,
                        color: AppColors.blue, size: 26),
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'Sign In',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.0,
                    ),
                  ),
                  Text(
                    auth.stationName ?? 'Connect to your station',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 15),
                  ),
                  const SizedBox(height: 32),

                  // Role selector
                  const Text(
                    'I am a',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _roles.map((r) {
                      final selected = _role == r.$1;
                      return ChoiceChip(
                        label: Text(r.$2),
                        selected: selected,
                        onSelected: (v) {
                          if (v) setState(() => _role = r.$1);
                        },
                        selectedColor: AppColors.blue,
                        labelStyle: TextStyle(
                          color: selected
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        backgroundColor: AppColors.bgApp,
                        side: BorderSide(
                          color: selected
                              ? AppColors.blue
                              : AppColors.textMuted.withValues(alpha: 0.3),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Phone number
                  AppTextField(
                    label: 'Mobile Number',
                    hint: 'Enter your registered phone',
                    controller: _phoneCtrl,
                    prefixIcon: Icons.phone_android_outlined,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (v.trim().length < 10) return 'Enter valid phone';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Credential field (PIN or Password)
                  Row(
                    children: [
                      Expanded(
                        child: Text(_usePin ? 'PIN' : 'Password',
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _usePin = !_usePin),
                        child: Text(
                          _usePin ? 'Use Password' : 'Use PIN',
                          style: const TextStyle(
                              color: AppColors.blue,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AppTextField(
                    label: '', // label already handled above
                    hint:
                        _usePin ? 'Enter 4-6 digit PIN' : 'Enter your password',
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
                        v == null || v.isEmpty ? 'Required' : null,
                  ),

                  if (auth.error != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.redBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.red.withValues(alpha: 0.2)),
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

                  const SizedBox(height: 32),
                  AppButton(
                    label: 'Sign In',
                    onTap: _login,
                    loading: auth.isLoading,
                    width: double.infinity,
                  ),

                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Station Code: ${auth.stationCode}',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
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
