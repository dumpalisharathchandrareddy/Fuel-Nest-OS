// ─── dealer_signup_screen.dart ────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/widgets/widgets.dart';
import '../../../core/utils/validators.dart';
import '../../../core/constants/app_constants.dart';
import 'package:flutter/services.dart';

class DealerSignupScreen extends ConsumerStatefulWidget {
  const DealerSignupScreen({super.key});

  @override
  ConsumerState<DealerSignupScreen> createState() => _DealerSignupScreenState();
}

class _DealerSignupScreenState extends ConsumerState<DealerSignupScreen> {
  final _form = GlobalKey<FormState>();
  final _step = ValueNotifier(0);

  // 'managed' | 'byo' | null (unselected on step 0)
  String? _dbMode;

  // Supabase credentials (BYO only)
  final _urlCtrl = TextEditingController();
  final _anonKeyCtrl = TextEditingController();

  // Station info
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _stateFocus = FocusNode();

  // Owner info
  final _ownerNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  // Total steps: managed = 3 (mode, station, owner), byo = 4 (mode, creds, station, owner)
  int get _totalSteps => _dbMode == 'byo' ? 4 : 3;

  // Visual step index for indicator (0-based, compressed for managed mode)
  bool get _isLastStep => _step.value == _totalSteps - 1;

  @override
  void dispose() {
    for (final c in [
      _urlCtrl,
      _anonKeyCtrl,
      _codeCtrl,
      _nameCtrl,
      _cityCtrl,
      _ownerNameCtrl,
      _phoneCtrl,
      _stateCtrl,
      _passwordCtrl,
      _confirmPassCtrl,
    ]) {
      c.dispose();
    }
    _stateFocus.dispose();
    _step.dispose();
    super.dispose();
  }

  void _onNext(int step) {
    if (step == 0) {
      // Mode selection: require a choice before proceeding
      if (_dbMode == null) {
        setState(() => _error = 'Please choose a database setup option.');
        return;
      }
      setState(() => _error = null);
      _step.value = 1;
      return;
    }
    if (_form.currentState!.validate()) {
      setState(() => _error = null);
      _step.value = step + 1;
    }
  }

  void _onBack(int step) {
    setState(() => _error = null);
    if (_dbMode == 'managed' && step == 2) {
      // managed: station info is step 2 (skips creds step 1), go back to step 0
      _step.value = 0;
    } else {
      _step.value = step - 1;
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final ok = await ref.read(authProvider.notifier).signup(
          stationCode: _codeCtrl.text.trim(),
          stationName: _nameCtrl.text.trim(),
          ownerName: _ownerNameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          password: _passwordCtrl.text,
          supabaseUrl: _urlCtrl.text.trim(),
          anonKey: _anonKeyCtrl.text.trim(),
          dbMode: _dbMode ?? 'byo',
          city: _cityCtrl.text.trim(),
          state: _stateCtrl.text.trim(),
        );
    if (!ok && mounted) {
      setState(() {
        _error = ref.read(authProvider).error;
      });
    }
    // On success, router redirect handles navigation (/signup → /app/dashboard)
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: const Text('Register Your Station'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Form(
                key: _form,
            child: ValueListenableBuilder(
              valueListenable: _step,
              builder: (_, step, __) {
                final totalBars = _dbMode == null ? 3 : _totalSteps;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step indicator
                    Row(
                      children: List.generate(
                        totalBars,
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
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (step == 0) ..._buildStep0(),
                    // BYO: step 1 = creds, step 2 = station, step 3 = owner
                    // managed: step 1 = station, step 2 = owner (step 1 in byo is skipped)
                    if (_dbMode == 'byo') ...[
                      if (step == 1) ..._buildStepCreds(),
                      if (step == 2) ..._buildStepStation(),
                      if (step == 3) ..._buildStepOwner(),
                    ] else ...[
                      if (step == 1) ..._buildStepStation(),
                      if (step == 2) ..._buildStepOwner(),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.redBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: AppColors.red, fontSize: 13),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    if (size.width < 360) ...[
                      AppButton(
                        label: _isLastStep ? 'Create Station' : 'Next',
                        loading: _loading,
                        onTap: _isLastStep ? _submit : () => _onNext(step),
                        width: double.infinity,
                      ),
                      if (step > 0) ...[
                        const SizedBox(height: 12),
                        AppButton(
                          label: 'Back',
                          secondary: true,
                          onTap: () => _onBack(step),
                          width: double.infinity,
                        ),
                      ],
                    ] else
                      Row(
                        children: [
                          if (step > 0) ...[
                            Expanded(
                              child: AppButton(
                                label: 'Back',
                                secondary: true,
                                onTap: () => _onBack(step),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: AppButton(
                              label: _isLastStep ? 'Create Station' : 'Next',
                              loading: _loading,
                              onTap: _isLastStep ? _submit : () => _onNext(step),
                            ),
                          ),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  ),
);
}

  List<Widget> _buildStep0() => [
        const Text(
          'Choose Database Setup',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'How would you like to store your station data?',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        _DbModeCard(
          selected: _dbMode == 'managed',
          icon: Icons.cloud_outlined,
          iconColor: AppColors.blue,
          iconBg: AppColors.blueBg,
          title: 'Use FuelOS Managed DB',
          subtitle: 'Recommended',
          description:
              'We host and manage the database for your station. No setup needed.',
          onTap: () => setState(() {
            _dbMode = 'managed';
            _error = null;
          }),
        ),
        const SizedBox(height: 12),
        _DbModeCard(
          selected: _dbMode == 'byo',
          icon: Icons.storage_outlined,
          iconColor: AppColors.purple,
          iconBg: AppColors.purpleBg,
          title: 'Connect My Own Supabase',
          subtitle: 'Advanced',
          description:
              'Use your own Supabase project and keep full database control.',
          onTap: () => setState(() {
            _dbMode = 'byo';
            _error = null;
          }),
        ),
      ];

  List<Widget> _buildStepCreds() => [
        const Text(
          'Connect Your Supabase',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Create a free Supabase project at supabase.com, then paste your Project URL and anon key below. Your data stays in your own database.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        AppTextField(
          label: 'Supabase Project URL',
          hint: 'https://xxxxx.supabase.co',
          controller: _urlCtrl,
          prefixIcon: Icons.link,
          keyboardType: TextInputType.url,
          validator: Validators.supabaseUrl,
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Supabase Anon Key',
          hint: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
          controller: _anonKeyCtrl,
          prefixIcon: Icons.vpn_key_outlined,
          validator: (v) => Validators.required(v, 'Anon Key'),
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
            style:
                TextStyle(color: AppColors.blue, fontSize: 12, height: 1.4),
          ),
        ),
      ];

  List<Widget> _buildStepStation() => [
        const Text(
          'Station Details',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 24),
        AppTextField(
          label: 'Station Code',
          hint: 'e.g. MYSTATION01 (unique, no spaces)',
          controller: _codeCtrl,
          prefixIcon: Icons.qr_code,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
          ],
          validator: Validators.stationCode,
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
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
          ],
          validator: (v) => Validators.name(v, 'Station Name'),
        ),
        const SizedBox(height: 16),
        if (MediaQuery.sizeOf(context).width < 700) ...[
          AppTextField(
            label: 'City',
            controller: _cityCtrl,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
            ],
            validator: Validators.city,
          ),
          const SizedBox(height: 16),
          AppAutocompleteField(
            label: 'State',
            controller: _stateCtrl,
            focusNode: _stateFocus,
            suggestions: AppConstants.indianStates,
            prefixIcon: Icons.map_outlined,
            validator: Validators.state,
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'City',
                  controller: _cityCtrl,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
                  ],
                  validator: Validators.city,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppAutocompleteField(
                  label: 'State',
                  controller: _stateCtrl,
                  focusNode: _stateFocus,
                  suggestions: AppConstants.indianStates,
                  prefixIcon: Icons.map_outlined,
                  validator: Validators.state,
                ),
              ),
            ],
          ),
      ];

  List<Widget> _buildStepOwner() => [
        const Text(
          'Your Account',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 24),
        AppTextField(
          label: 'Your Full Name',
          controller: _ownerNameCtrl,
          prefixIcon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
          ],
          validator: (v) => Validators.name(v, 'Full Name'),
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Mobile Number',
          controller: _phoneCtrl,
          prefixIcon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          validator: Validators.phone,
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Password',
          controller: _passwordCtrl,
          obscure: true,
          prefixIcon: Icons.lock_outline,
          validator: Validators.password,
        ),
        const SizedBox(height: 16),
        AppTextField(
          label: 'Confirm Password',
          controller: _confirmPassCtrl,
          obscure: true,
          prefixIcon: Icons.lock_outline,
          validator: (v) => Validators.confirmPassword(v, _passwordCtrl.text),
        ),
      ];
}

// ─── _DbModeCard ──────────────────────────────────────────────────────────────

class _DbModeCard extends StatelessWidget {
  const _DbModeCard({
    required this.selected,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.blue : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.greenBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.green,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.blue : Colors.transparent,
                border: Border.all(
                  color: selected ? AppColors.blue : AppColors.borderMd,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 12)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
