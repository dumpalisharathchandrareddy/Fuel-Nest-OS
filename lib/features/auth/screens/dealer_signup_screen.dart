// ─── dealer_signup_screen.dart ────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/widgets/widgets.dart';

class DealerSignupScreen extends ConsumerStatefulWidget {
  const DealerSignupScreen({super.key});

  @override
  ConsumerState<DealerSignupScreen> createState() => _DealerSignupScreenState();
}

class _DealerSignupScreenState extends ConsumerState<DealerSignupScreen> {
  final _form = GlobalKey<FormState>();
  final _step = ValueNotifier(0); // 0 = supabase, 1 = station info, 2 = owner

  // Supabase credentials (Step 0)
  final _urlCtrl = TextEditingController();
  final _anonKeyCtrl = TextEditingController();

  // Station info (Step 1)
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();

  // Owner info (Step 2)
  final _ownerNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _urlCtrl,
      _anonKeyCtrl,
      _codeCtrl,
      _nameCtrl,
      _cityCtrl,
      _stateCtrl,
      _ownerNameCtrl,
      _phoneCtrl,
      _passwordCtrl,
      _confirmPassCtrl,
    ]) {
      c.dispose();
    }
    _step.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await DealerSetupService.instance.signupDealer(
        stationCode: _codeCtrl.text.trim(),
        stationName: _nameCtrl.text.trim(),
        ownerName: _ownerNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        password: _passwordCtrl.text,
        supabaseUrl: _urlCtrl.text.trim(),
        anonKey: _anonKeyCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim(),
      );
      if (mounted) context.go('/app/dashboard');
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: const Text('Register Your Station'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.go('/station'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? size.width * 0.25 : 24,
            vertical: 24,
          ),
          child: Form(
            key: _form,
            child: ValueListenableBuilder(
              valueListenable: _step,
              builder: (_, step, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step indicator
                  Row(
                    children: List.generate(
                        3,
                        (i) => Expanded(
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                height: 3,
                                decoration: BoxDecoration(
                                  color: i <= step
                                      ? AppColors.blue
                                      : AppColors.border,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            )),
                  ),
                  const SizedBox(height: 24),

                  if (step == 0) ..._buildStep0(),
                  if (step == 1) ..._buildStep1(),
                  if (step == 2) ..._buildStep2(),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.redBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.red, fontSize: 13)),
                    ),
                  ],

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (step > 0) ...[
                        Expanded(
                          child: AppButton(
                            label: 'Back',
                            secondary: true,
                            onTap: () => _step.value = step - 1,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: AppButton(
                          label: step < 2 ? 'Next' : 'Create Station',
                          loading: _loading,
                          onTap: step < 2
                              ? () {
                                  if (_form.currentState!.validate()) {
                                    _step.value = step + 1;
                                  }
                                }
                              : _submit,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStep0() => [
        const Text('Connect Your Supabase',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Create a free Supabase project at supabase.com, then paste your Project URL and anon key below. Your data stays in your own database.',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        AppTextField(
          label: 'Supabase Project URL',
          hint: 'https://xxxxx.supabase.co',
          controller: _urlCtrl,
          prefixIcon: Icons.link,
          keyboardType: TextInputType.url,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            if (!v.trim().contains('supabase.co')) {
              return 'Enter a valid Supabase URL';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Supabase Anon Key',
          hint: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
          controller: _anonKeyCtrl,
          prefixIcon: Icons.vpn_key_outlined,
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
          maxLines: 3,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.blueBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '🔒 Your Supabase credentials are stored only on this device. Managers and staff never see them.',
            style: TextStyle(color: AppColors.blue, fontSize: 12, height: 1.4),
          ),
        ),
      ];

  List<Widget> _buildStep1() => [
        const Text('Station Details',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        AppTextField(
          label: 'Station Code',
          hint: 'e.g. MYSTATION01 (unique, no spaces)',
          controller: _codeCtrl,
          prefixIcon: Icons.qr_code,
          textCapitalization: TextCapitalization.characters,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            if (v.trim().length < 4) return 'At least 4 characters';
            if (v.trim().contains(' ')) return 'No spaces allowed';
            return null;
          },
        ),
        const SizedBox(height: 12),
        const Text(
          'Staff and creditors use this code to connect to your station.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Station Name',
          hint: 'e.g. Ram Fuels Petrol Bunk',
          controller: _nameCtrl,
          prefixIcon: Icons.store_outlined,
          textCapitalization: TextCapitalization.words,
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                label: 'City',
                controller: _cityCtrl,
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                label: 'State',
                controller: _stateCtrl,
                textCapitalization: TextCapitalization.words,
              ),
            ),
          ],
        ),
      ];

  List<Widget> _buildStep2() => [
        const Text('Your Account',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 24),
        AppTextField(
          label: 'Your Full Name',
          controller: _ownerNameCtrl,
          prefixIcon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Mobile Number',
          controller: _phoneCtrl,
          prefixIcon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Required';
            if (v.trim().length < 10) return 'Enter valid mobile number';
            return null;
          },
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Password',
          controller: _passwordCtrl,
          obscure: true,
          prefixIcon: Icons.lock_outline,
          validator: (v) {
            if (v == null || v.isEmpty) return 'Required';
            if (v.length < 6) return 'Minimum 6 characters';
            return null;
          },
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Confirm Password',
          controller: _confirmPassCtrl,
          obscure: true,
          prefixIcon: Icons.lock_outline,
          validator: (v) {
            if (v != _passwordCtrl.text) return 'Passwords do not match';
            return null;
          },
        ),
      ];
}
