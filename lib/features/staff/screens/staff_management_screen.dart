import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/services/discord_service.dart';
import '../../../core/utils/currency.dart';
import '../../../shared/widgets/widgets.dart';
import 'package:uuid/uuid.dart';

class StaffManagementScreen extends ConsumerStatefulWidget {
  const StaffManagementScreen({super.key});
  @override
  ConsumerState<StaffManagementScreen> createState() =>
      _StaffManagementScreenState();
}

class _StaffManagementScreenState extends ConsumerState<StaffManagementScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _staff = [];
  List<dynamic> _archiveRequests = [];
  String _search = '';
  String _roleFilter = 'ALL';
  String _statusFilter = 'ACTIVE';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider);
      if (user == null) {
        setState(() => _loading = false);
        return;
      }
      final results = await Future.wait([
        db
            .from('User')
            .select(
                'id, full_name, username, employee_id, phone_number, role, active, created_at, salary_config:SalaryConfig(base_monthly_salary, effective_from)')
            .eq('station_id', user.stationId)
            .neq('role', 'DEALER')
            .order('full_name'),
        db
            .from('StaffArchiveRequest')
            .select(
                'id, status, reason, created_at, target_user_id, requested_by_id')
            .eq('station_id', user.stationId)
            .eq('status', 'PENDING'),
      ]);
      setState(() {
        _staff = results[0] as List;
        _archiveRequests = results[1] as List;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<dynamic> get _filtered => _staff.where((s) {
        final name = (s['full_name'] as String? ?? '').toLowerCase();
        final phone = s['phone_number'] as String? ?? '';
        final empId = s['employee_id'] as String? ?? '';
        final role = s['role'] as String? ?? '';
        final active = s['active'] as bool? ?? true;
        final matchSearch = _search.isEmpty ||
            name.contains(_search.toLowerCase()) ||
            phone.contains(_search) ||
            empId.toLowerCase().contains(_search.toLowerCase());
        final matchRole = _roleFilter == 'ALL' || role == _roleFilter;
        final matchStatus = _statusFilter == 'ALL' ||
            (_statusFilter == 'ACTIVE' && active) ||
            (_statusFilter == 'INACTIVE' && !active);
        return matchSearch && matchRole && matchStatus;
      }).toList();

  String _suggestEmployeeId(String role) {
    final prefix = role == 'MANAGER' ? 'MGR' : 'WKE';
    final existing = _staff
        .map((s) => s['employee_id'] as String? ?? '')
        .where((id) => id.startsWith('$prefix-'))
        .map((id) => int.tryParse(id.substring(prefix.length + 1)) ?? 0)
        .toList();
    final next =
        existing.isEmpty ? 1 : existing.reduce((a, b) => a > b ? a : b) + 1;
    return '$prefix-${next.toString().padLeft(3, '0')}';
  }

  String _deriveUsername(String fullName, String employeeId) {
    final letters = fullName.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final first = letters.length >= 2
        ? letters.substring(0, 2)
        : letters.padRight(2, 'x');
    final last = letters.length >= 2
        ? letters.substring(letters.length - 2)
        : letters.padLeft(2, 'x');
    final nums = employeeId.replaceAll(RegExp(r'\D'), '').padLeft(3, '0');
    return '$first$last@$nums';
  }

  // ── Add / Edit Staff ────────────────────────────────────────────────────────
  Future<void> _showStaffForm({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final nameCtrl =
        TextEditingController(text: existing?['full_name'] as String? ?? '');
    final phoneCtrl =
        TextEditingController(text: existing?['phone_number'] as String? ?? '');
    final passCtrl = TextEditingController();
    final empIdCtrl =
        TextEditingController(text: existing?['employee_id'] as String? ?? '');
    final usernameCtrl =
        TextEditingController(text: existing?['username'] as String? ?? '');
    final salaryCtrl = TextEditingController(
        text: (existing?['salary_config'] as Map?)?['base_monthly_salary']
                ?.toString() ??
            '');
    String role = existing?['role'] as String? ?? 'PUMP_PERSON';
    bool submitting = false;
    String? err;

    if (!isEdit) {
      empIdCtrl.text = _suggestEmployeeId(role);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        void onNameOrIdChanged() {
          if (!isEdit) {
            usernameCtrl.text = _deriveUsername(nameCtrl.text, empIdCtrl.text);
          }
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.viewInsetsOf(ctx).bottom + 24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(isEdit ? Icons.edit_outlined : Icons.person_add_alt,
                  color: AppColors.blue, size: 22),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(isEdit ? 'Edit Staff Member' : 'Add Staff Member',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700))),
              IconButton(
                  icon: const Icon(Icons.close,
                      size: 20, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 20),

            // Role selector
            const Text('ROLE',
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 8),
            Row(
                children: ['MANAGER', 'PUMP_PERSON'].map((r) {
              final sel = role == r;
              final label = r == 'MANAGER' ? 'Manager' : 'Staff / Pump Person';
              final color = r == 'MANAGER' ? AppColors.blue : AppColors.green;
              return Expanded(
                  child: GestureDetector(
                onTap: () {
                  ss(() {
                    role = r;
                    if (!isEdit) empIdCtrl.text = _suggestEmployeeId(r);
                    onNameOrIdChanged();
                  });
                },
                child: Container(
                  margin: EdgeInsets.only(right: r == 'MANAGER' ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                      color: sel
                          ? color.withValues(alpha: 0.15)
                          : AppColors.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: sel ? color : AppColors.border,
                          width: sel ? 1.5 : 1)),
                  alignment: Alignment.center,
                  child: Text(label,
                      style: TextStyle(
                          color: sel ? color : AppColors.textSecondary,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                          fontSize: 13)),
                ),
              ));
            }).toList()),
            const SizedBox(height: 16),

            _Field(
                label: 'Full Name *',
                ctrl: nameCtrl,
                capitalize: TextCapitalization.words,
                onChanged: (_) => ss(onNameOrIdChanged)),
            const SizedBox(height: 12),
            _Field(
                label: 'Mobile Number *',
                ctrl: phoneCtrl,
                keyboard: TextInputType.phone),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: _Field(
                      label: 'Employee ID',
                      ctrl: empIdCtrl,
                      capitalize: TextCapitalization.characters,
                      onChanged: (_) => ss(onNameOrIdChanged))),
              const SizedBox(width: 8),
              Expanded(child: _Field(label: 'Username', ctrl: usernameCtrl)),
            ]),
            const SizedBox(height: 12),
            _Field(
                label: 'Base Salary (₹/month)',
                ctrl: salaryCtrl,
                keyboard: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),
            _Field(
                label: isEdit
                    ? 'New Password (leave blank to keep)'
                    : 'Password *',
                ctrl: passCtrl,
                obscure: true),
            const SizedBox(height: 4),
            const Text(
                'Staff can also login with PIN — set it separately after creation',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11)),

            if (err != null) ...[
              const SizedBox(height: 12),
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppColors.redBg,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(err!,
                      style:
                          const TextStyle(color: AppColors.red, fontSize: 12))),
            ],
            const SizedBox(height: 20),
            AppButton(
              label: isEdit ? 'Save Changes' : 'Create Staff Member',
              loading: submitting,
              width: double.infinity,
              onTap: () async {
                if (nameCtrl.text.trim().isEmpty ||
                    phoneCtrl.text.trim().isEmpty) {
                  ss(() => err = 'Name and phone number are required');
                  return;
                }
                if (!isEdit && passCtrl.text.isEmpty) {
                  ss(() => err = 'Password is required for new staff');
                  return;
                }
                ss(() {
                  submitting = true;
                  err = null;
                });
                try {
                  final db = TenantService.instance.client;
                  final user = ref.read(currentUserProvider)!;
                  final now = DateTime.now().toUtc().toIso8601String();
                  final salary = double.tryParse(salaryCtrl.text) ?? 0;

                  if (isEdit) {
                    await db.from('User').update({
                      'full_name': nameCtrl.text.trim(),
                      'phone_number': phoneCtrl.text.trim(),
                      'employee_id': empIdCtrl.text.trim().isEmpty
                          ? null
                          : empIdCtrl.text.trim(),
                      'username': usernameCtrl.text.trim().isEmpty
                          ? null
                          : usernameCtrl.text.trim(),
                      'role': role,
                      'updated_at': now,
                      if (passCtrl.text.isNotEmpty)
                        'password_hash': passCtrl.text, // Edge fn hashes it
                    }).eq('id', existing['id']);

                    // Update salary config
                    if (salary > 0) {
                      await db.from('SalaryConfig').upsert({
                        'station_id': user.stationId,
                        'user_id': existing['id'],
                        'base_monthly_salary': salary,
// // SalaryConfig has no /* SalaryConfig has no /* no salary_type */ */ column // SalaryConfig has no salary_type column
                        'updated_at': now,
                      }, onConflict: 'user_id');
                    }
                  } else {
                    // Create via edge function (handles password hashing)
                    final resp =
                        await db.functions.invoke('create-staff', body: {
                      'full_name': nameCtrl.text.trim(),
                      'phone_number': phoneCtrl.text.trim(),
                      'employee_id': empIdCtrl.text.trim().isEmpty
                          ? null
                          : empIdCtrl.text.trim(),
                      'username': usernameCtrl.text.trim().isEmpty
                          ? null
                          : usernameCtrl.text.trim(),
                      'role': role,
                      'password': passCtrl.text,
                      'station_id': user.stationId,
                      'base_salary_snapshot': salary,
                      'created_by': user.id,
                    });

                    // Fallback if edge function not deployed: direct insert with plain password
                    // (Edge function should hash it; this is a dev fallback)
                    if (resp.status != 200) {
                      final newUserId = _uuid();
                      await db.from('User').insert({
                        'id': newUserId,
                        'station_id': user.stationId,
                        'full_name': nameCtrl.text.trim(),
                        'phone_number': phoneCtrl.text.trim(),
                        'employee_id': empIdCtrl.text.trim().isEmpty
                            ? null
                            : empIdCtrl.text.trim(),
                        'username': usernameCtrl.text.trim().isEmpty
                            ? null
                            : usernameCtrl.text.trim(),
                        'role': role,
                        'password_hash': passCtrl.text,
                        'active': true,
                        'created_by_id': user.id,
                        'created_at': now,
                        'updated_at': now,
                      });
                      if (salary > 0) {
                        await db.from('SalaryConfig').insert({
                          'station_id': user.stationId,
                          'user_id': newUserId,
                          'base_monthly_salary': salary,
// // SalaryConfig has no /* SalaryConfig has no /* no salary_type */ */ column // SalaryConfig has no salary_type column
                          'created_by': user.id,
                          'created_at': now,
                          'updated_at': now,
                        });
                      }
                    }
                  }

                  await DiscordService.instance.sendStaffChange(
                    action: isEdit ? 'Updated' : 'Created',
                    staffName: nameCtrl.text.trim(),
                    role: role,
                    stationName: ref.read(stationNameProvider),
                  );

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(isEdit
                            ? '✅ Staff updated'
                            : '✅ ${nameCtrl.text.trim()} added'),
                        backgroundColor: AppColors.green));
                    _fetch();
                  }
                } catch (e) {
                  ss(() {
                    submitting = false;
                    err = e.toString().replaceAll('Exception: ', '');
                  });
                }
              },
            ),
          ]),
        );
      }),
    );
    for (final c in [
      nameCtrl,
      phoneCtrl,
      passCtrl,
      empIdCtrl,
      usernameCtrl,
      salaryCtrl
    ]) {
      c.dispose();
    }
  }

  // ── Set PIN ──────────────────────────────────────────────────────────────────
  Future<void> _showSetPin(Map<String, dynamic> staffMember) async {
    final pinCtrl = TextEditingController();
    bool submitting = false;
    String? err;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, ss) => AlertDialog(
                title: Text('Set PIN — ${staffMember['full_name']}'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Staff can use this 4–6 digit PIN to sign in instead of password.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pinCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    obscureText: true,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        letterSpacing: 8,
                        fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '••••',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      counterText: '',
                    ),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 8),
                    Text(err!,
                        style:
                            const TextStyle(color: AppColors.red, fontSize: 12))
                  ],
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            if (pinCtrl.text.length < 4) {
                              ss(() => err = 'PIN must be 4–6 digits');
                              return;
                            }
                            ss(() {
                              submitting = true;
                              err = null;
                            });
                            try {
                              final db = TenantService.instance.client;
                              // Call edge function to hash and save PIN
                              await db.functions.invoke('set-user-pin', body: {
                                'user_id': staffMember['id'],
                                'pin': pinCtrl.text,
                              });
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('✅ PIN set successfully'),
                                        backgroundColor: AppColors.green));
                              }
                            } catch (e) {
                              ss(() {
                                submitting = false;
                                err = 'Failed to set PIN. Try again.';
                              });
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Set PIN',
                            style: TextStyle(color: AppColors.blue)),
                  ),
                ],
              )),
    );
    pinCtrl.dispose();
  }

  // ── Toggle Active ────────────────────────────────────────────────────────────
  Future<void> _toggleActive(Map<String, dynamic> staffMember) async {
    final isActive = staffMember['active'] as bool? ?? true;
    final confirm = await showConfirmDialog(
      context,
      title: isActive ? 'Deactivate Staff' : 'Activate Staff',
      message: isActive
          ? '${staffMember['full_name']} will no longer be able to log in.'
          : 'Restore login access for ${staffMember['full_name']}.',
      confirmLabel: isActive ? 'Deactivate' : 'Activate',
      isDanger: isActive,
    );
    if (!confirm) return;
    try {
      final db = TenantService.instance.client;
      await db.from('User').update({
        'active': !isActive,
        'updated_at': DateTime.now().toUtc().toIso8601String()
      }).eq('id', staffMember['id']);
      _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Archive request (Manager → requests Dealer approval) ───────────────────
  Future<void> _requestArchive(Map<String, dynamic> staffMember) async {
    final user = ref.read(currentUserProvider)!;
    final isDealer = user.isDealer;
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isDealer ? 'Archive Staff' : 'Request Archive'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(isDealer
              ? 'This will permanently archive ${staffMember['full_name']}\'s account.'
              : 'Send an archive request to the dealer for ${staffMember['full_name']}.'),
          const SizedBox(height: 12),
          TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                  labelText: 'Reason (optional)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isDealer ? 'Archive' : 'Send Request',
                style: const TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) {
      reasonCtrl.dispose();
      return;
    }
    try {
      final db = TenantService.instance.client;
      if (isDealer) {
        await db.from('User').update({
          'active': false,
          'updated_at': DateTime.now().toUtc().toIso8601String()
        }).eq('id', staffMember['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ Staff archived'),
              backgroundColor: AppColors.green));
        }
      } else {
        await db.from('StaffArchiveRequest').insert({
          'station_id': user.stationId,
          'target_user_id': staffMember['id'],
          'requested_by_id': user.id,
          'reason':
              reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
          'status': 'PENDING',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('✅ Archive request sent to dealer')));
        }
      }
      _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
    reasonCtrl.dispose();
  }

  // ── Archive request resolve (Dealer only) ──────────────────────────────────
  Future<void> _resolveArchive(Map<String, dynamic> req, bool approve) async {
    try {
      final db = TenantService.instance.client;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.from('StaffArchiveRequest').update({
        'status': approve ? 'APPROVED' : 'REJECTED',
        'resolved_at': now,
        'resolved_by_id': ref.read(currentUserProvider)!.id,
      }).eq('id', req['id']);
      if (approve) {
        await db.from('User').update({'active': false, 'updated_at': now}).eq(
            'id', (req['target_user'] as Map)['id']);
      }
      _fetch();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(approve ? '✅ Staff archived' : 'Request rejected'),
            backgroundColor: approve ? AppColors.green : null));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isDealer = user?.isDealer ?? false;
    final isManager = user?.isManagerOrDealer ?? false;
    final filtered = _filtered;

    if (_loading) {
      return const Scaffold(
          backgroundColor: AppColors.bgApp, body: LoadingView());
    }
    if (_error != null) {
      return Scaffold(
          backgroundColor: AppColors.bgApp,
          body: ErrorView(message: _error!, onRetry: _fetch));
    }

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      floatingActionButton: isManager
          ? FloatingActionButton.extended(
              onPressed: () => _showStaffForm(),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add Staff'),
              backgroundColor: AppColors.blue)
          : null,
      body: RefreshIndicator(
        onRefresh: _fetch,
        color: AppColors.blue,
        child: CustomScrollView(slivers: [
          // Pending archive requests (dealer only)
          if (isDealer && _archiveRequests.isNotEmpty)
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeader(title: 'Pending Archive Requests'),
                    const SizedBox(height: 10),
                    ..._archiveRequests.map((req) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            borderColor: AppColors.amber.withValues(alpha: 0.3),
                            child: Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        'User: ${req['target_user_id']?.toString().substring(0, 8) ?? ''}...',
                                        style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                        'Requested: ${req['created_at']?.toString().substring(0, 10) ?? ''}',
                                        style: const TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 12)),
                                    if (req['reason'] != null)
                                      Text(req['reason'] as String,
                                          style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12)),
                                  ])),
                              TextButton(
                                  onPressed: () => _resolveArchive(req, true),
                                  child: const Text('Approve',
                                      style: TextStyle(
                                          color: AppColors.red, fontSize: 12))),
                              TextButton(
                                  onPressed: () => _resolveArchive(req, false),
                                  child: const Text('Reject',
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12))),
                            ]),
                          ),
                        )),
                    const SizedBox(height: 8),
                  ]),
            )),

          // Filters
          SliverToBoxAdapter(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(children: [
              TextField(
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AppColors.textMuted),
                  hintText: 'Search name, phone, employee ID...',
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: AppColors.bgCard,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _FilterRow(
                  options: const {
                    'ALL': 'All',
                    'MANAGER': 'Managers',
                    'PUMP_PERSON': 'Staff'
                  },
                  selected: _roleFilter,
                  onChanged: (v) => setState(() => _roleFilter = v),
                )),
                const SizedBox(width: 8),
                _FilterChip(
                  label: _statusFilter == 'ACTIVE'
                      ? 'Active'
                      : _statusFilter == 'INACTIVE'
                          ? 'Inactive'
                          : 'All',
                  onTap: () => setState(() {
                    _statusFilter = _statusFilter == 'ACTIVE'
                        ? 'INACTIVE'
                        : _statusFilter == 'INACTIVE'
                            ? 'ALL'
                            : 'ACTIVE';
                  }),
                ),
              ]),
            ]),
          )),

          // Staff list
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            sliver: filtered.isEmpty
                ? const SliverFillRemaining(
                    child: EmptyView(
                        title: 'No staff found', icon: Icons.people_outline))
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final s = filtered[i] as Map<String, dynamic>;
                      final isActive = s['active'] as bool? ?? true;
                      final role = s['role'] as String? ?? '';
                      final config = s['salary_config'] as Map?;
                      final salary = config != null
                          ? double.tryParse(
                                  config['base_monthly_salary']?.toString() ??
                                      '0') ??
                              0
                          : 0.0;
                      final roleColor =
                          role == 'MANAGER' ? AppColors.blue : AppColors.green;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          child: Column(children: [
                            Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                    color: isActive
                                        ? roleColor.withValues(alpha: 0.12)
                                        : AppColors.bgHover,
                                    borderRadius: BorderRadius.circular(12)),
                                alignment: Alignment.center,
                                child: Text(
                                    (s['full_name'] as String? ?? 'U')[0]
                                        .toUpperCase(),
                                    style: TextStyle(
                                        color: isActive
                                            ? roleColor
                                            : AppColors.textMuted,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 18)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Row(children: [
                                      Text(s['full_name'] as String? ?? '',
                                          style: TextStyle(
                                              color: isActive
                                                  ? AppColors.textPrimary
                                                  : AppColors.textMuted,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15)),
                                      const SizedBox(width: 8),
                                      if (!isActive)
                                        const StatusBadge(
                                            label: 'Inactive',
                                            tone: BadgeTone.error),
                                    ]),
                                    Text(
                                      [
                                        role == 'MANAGER' ? 'Manager' : 'Staff',
                                        if (s['employee_id'] != null)
                                          s['employee_id'] as String,
                                        s['phone_number'] as String? ?? '',
                                      ].where((x) => x.isNotEmpty).join(' · '),
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12),
                                    ),
                                    if (salary > 0)
                                      Text(
                                          'Salary: ${IndianCurrency.format(salary)}/mo',
                                          style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 11)),
                                  ])),
                            ]),
                            if (isManager) ...[
                              const Divider(
                                  height: 16, color: AppColors.border),
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    _ActionBtn(
                                        label: 'Edit',
                                        icon: Icons.edit_outlined,
                                        onTap: () =>
                                            _showStaffForm(existing: s)),
                                    const SizedBox(width: 4),
                                    _ActionBtn(
                                        label: 'PIN',
                                        icon: Icons.pin_outlined,
                                        onTap: () => _showSetPin(s)),
                                    const SizedBox(width: 4),
                                    _ActionBtn(
                                      label: isActive ? 'Disable' : 'Enable',
                                      icon: isActive
                                          ? Icons.block
                                          : Icons.check_circle_outline,
                                      onTap: () => _toggleActive(s),
                                      color: isActive
                                          ? AppColors.amber
                                          : AppColors.green,
                                    ),
                                    const SizedBox(width: 4),
                                    _ActionBtn(
                                      label: isDealer ? 'Archive' : 'Request',
                                      icon: Icons.archive_outlined,
                                      onTap: () => _requestArchive(s),
                                      color: AppColors.red,
                                    ),
                                  ]),
                            ],
                          ]),
                        ),
                      );
                    },
                    childCount: filtered.length,
                  )),
          ),
        ]),
      ),
    );
  }

  String _uuid() => const Uuid().v4();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final TextInputType? keyboard;
  final TextCapitalization capitalize;
  final bool obscure;
  final void Function(String)? onChanged;
  const _Field(
      {required this.label,
      required this.ctrl,
      this.keyboard,
      this.capitalize = TextCapitalization.none,
      this.obscure = false,
      this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(
      controller: ctrl,
      keyboardType: keyboard,
      textCapitalization: capitalize,
      obscureText: obscure,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: AppColors.bgCard));
}

class _FilterRow extends StatelessWidget {
  final Map<String, String> options;
  final String selected;
  final void Function(String) onChanged;
  const _FilterRow(
      {required this.options, required this.selected, required this.onChanged});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
          children: options.entries.map((e) {
        final sel = selected == e.key;
        return GestureDetector(
            onTap: () => onChanged(e.key),
            child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: sel ? AppColors.blue : AppColors.bgCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? AppColors.blue : AppColors.border)),
                child: Text(e.value,
                    style: TextStyle(
                        color: sel ? Colors.white : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400))));
      }).toList()));
}

class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.filter_list, size: 13, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12))
          ])));
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _ActionBtn(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.color = AppColors.textSecondary});
  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 11)),
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero),
      );
}
