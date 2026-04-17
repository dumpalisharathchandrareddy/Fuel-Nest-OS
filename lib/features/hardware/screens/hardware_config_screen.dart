// hardware_config_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/constants/app_constants.dart';
import 'package:uuid/uuid.dart';
import '../../../shared/widgets/widgets.dart';

class HardwareConfigScreen extends ConsumerStatefulWidget {
  const HardwareConfigScreen({super.key});
  @override
  ConsumerState<HardwareConfigScreen> createState() =>
      _HardwareConfigScreenState();
}

class _HardwareConfigScreenState extends ConsumerState<HardwareConfigScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _pumps = [];
  List<dynamic> _tanks = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final results = await Future.wait([
        db
            .from('Pump')
            .select(
                'id, name, provider_type, active, nozzles:Nozzle(id, label, fuel_type, active, tank_id, default_testing)')
            .eq('station_id', user.stationId)
            .order('name'),
        db
            .from('Tank')
            .select(
                'id, name, fuel_type, capacity_liters, active, low_stock_threshold')
            .eq('station_id', user.stationId)
            .order('name'),
      ]);
      setState(() {
        _pumps = results[0];
        _tanks = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!silent) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _showTankForm({Map<String, dynamic>? existing}) async {
    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TankFormSheet(existing: existing),
    );
    if (success == true) _fetch(silent: true);
  }

  Future<void> _showPumpForm({Map<String, dynamic>? existing}) async {
    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PumpFormSheet(existing: existing),
    );
    if (success == true) _fetch(silent: true);
  }

  Future<void> _showNozzleForm(
      {required String pumpId, Map<String, dynamic>? existing}) async {
    final success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NozzleFormSheet(pumpId: pumpId, existing: existing),
    );
    if (success == true) _fetch(silent: true);
  }

  Future<void> _deleteHardware(String type, String id) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete $type',
      message: 'Are you sure you want to delete this $type?',
      confirmLabel: 'Delete',
      isDanger: true,
    );
    if (!ok) return;

    try {
      final db = TenantService.instance.client;

      // Dependency checks
      if (type == 'Tank') {
        final res = await db.from('Nozzle').select('id').eq('tank_id', id);
        final nozzleCount = (res as List).length;
        if (nozzleCount > 0) {
          throw 'Cannot delete: This tank is linked to $nozzleCount nozzle(s). Deactivate it instead.';
        }
        final dip = await db.from('DipReading').select('id').eq('tank_id', id);
        if ((dip as List).isNotEmpty) {
          throw 'Cannot delete: This tank has existing dip readings. Deactivate it instead.';
        }
      } else if (type == 'Pump') {
        final n = await db.from('Nozzle').select('id').eq('pump_id', id);
        final nozzleCount = (n as List).length;
        if (nozzleCount > 0) {
          throw 'Cannot delete: This pump has $nozzleCount nozzle(s). Delete nozzles first.';
        }
        final s = await db.from('Shift').select('id').eq('pump_id', id);
        if ((s as List).isNotEmpty) {
          throw 'Cannot delete: This pump has shift history. Deactivate it instead.';
        }
      } else if (type == 'Nozzle') {
        final e = await db.from('NozzleEntry').select('id').eq('nozzle_id', id);
        if ((e as List).isNotEmpty) {
          throw 'Cannot delete: This nozzle has reading entries. Deactivate it instead.';
        }
      }

      await db.from(type).delete().eq('id', id);
      _fetch(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          backgroundColor: AppColors.bgApp, body: LoadingView());
    }
    if (_error != null) {
      return Scaffold(
          backgroundColor: AppColors.bgApp,
          body: ErrorView(message: _error!, onRetry: _fetch));
    }

    final user = ref.watch(currentUserProvider);
    final isManager = user?.isManagerOrDealer ?? false;

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionHeader(
          title: 'Pumps & Nozzles',
          action: isManager ? 'Add Pump' : null,
          onAction: isManager ? () => _showPumpForm() : null,
        ),
        const SizedBox(height: 12),
        if (_pumps.isEmpty)
          EmptyView(
            title: 'No pumps configured yet',
            subtitle: isManager
                ? 'Tap Add Pump to configure your first pump'
                : 'Pumps and nozzles appear here once configured',
            icon: Icons.local_gas_station_outlined,
            action: isManager
                ? AppButton(
                    label: 'Add Pump',
                    onTap: () => _showPumpForm(),
                    width: 150)
                : null,
          )
        else
          ..._pumps.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        const Icon(Icons.local_gas_station,
                            color: AppColors.blue, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(p['name'] as String? ?? '',
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700))),
                        StatusBadge(
                            label: p['provider_type'] as String? ?? 'MANUAL',
                            tone: BadgeTone.info),
                        const SizedBox(width: 6),
                        StatusBadge(
                            label: p['active'] == true ? 'Active' : 'Inactive',
                            tone: p['active'] == true
                                ? BadgeTone.success
                                : BadgeTone.error),
                        if (isManager) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _showPumpForm(
                                existing: Map<String, dynamic>.from(p)),
                            child: const Icon(Icons.edit_outlined,
                                size: 16, color: AppColors.textMuted),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () =>
                                _deleteHardware('Pump', p['id'] as String),
                            child: const Icon(Icons.delete_outline,
                                size: 16, color: AppColors.red),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 12),
                      ...(p['nozzles'] as List? ?? []).map((n) {
                        final nMap = n as Map<String, dynamic>;
                        return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(children: [
                              const SizedBox(width: 26),
                              Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                      color: AppColors.textMuted,
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(
                                      '${nMap['label']} — ${nMap['fuel_type']}',
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13))),
                              StatusBadge(
                                  label: nMap['active'] == true ? 'On' : 'Off',
                                  tone: nMap['active'] == true
                                      ? BadgeTone.success
                                      : BadgeTone.error),
                              if (isManager) ...[
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: () => _showNozzleForm(
                                      pumpId: p['id'] as String,
                                      existing: nMap),
                                  child: const Icon(Icons.edit_outlined,
                                      size: 14, color: AppColors.textMuted),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _deleteHardware(
                                      'Nozzle', nMap['id'] as String),
                                  child: const Icon(Icons.delete_outline,
                                      size: 14, color: AppColors.red),
                                ),
                              ],
                            ]));
                      }),
                      if (isManager)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 24),
                          child: TextButton.icon(
                            onPressed: () =>
                                _showNozzleForm(pumpId: p['id'] as String),
                            icon: const Icon(Icons.add_circle_outline, size: 16),
                            label: const Text('Add Nozzle',
                                style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.blue,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                    ])),
              )),
        const SizedBox(height: 24),
        SectionHeader(
          title: 'Tanks',
          action: isManager ? 'Add Tank' : null,
          onAction: isManager ? () => _showTankForm() : null,
        ),
        const SizedBox(height: 12),
        if (_tanks.isEmpty)
          EmptyView(
            title: 'No tanks configured yet',
            subtitle: isManager
                ? 'Tap Add Tank to configure fuel tanks'
                : 'Tanks appear here once configured',
            icon: Icons.water_outlined,
            action: isManager
                ? AppButton(
                    label: 'Add Tank',
                    onTap: () => _showTankForm(),
                    width: 150)
                : null,
          )
        else
          ..._tanks.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                    child: Row(children: [
                  const Icon(Icons.water, color: AppColors.blue, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(t['name'] as String? ?? '',
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600)),
                        Text(
                            '${t['fuel_type']} · ${t['capacity_liters']} L capacity',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                      ])),
                  StatusBadge(
                      label: t['active'] == true ? 'Active' : 'Inactive',
                      tone: t['active'] == true
                          ? BadgeTone.success
                          : BadgeTone.error),
                  if (isManager) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => _showTankForm(
                          existing: Map<String, dynamic>.from(t)),
                      child: const Icon(Icons.edit_outlined,
                          size: 16, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _deleteHardware('Tank', t['id'] as String),
                      child: const Icon(Icons.delete_outline,
                          size: 16, color: AppColors.red),
                    ),
                  ],
                ])),
              )),
      ]),
    );
  }
}



// ── Modals ───────────────────────────────────────────────────────────────────

class TankFormSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  const TankFormSheet({super.key, this.existing});
  @override
  ConsumerState<TankFormSheet> createState() => _TankFormSheetState();
}

class _TankFormSheetState extends ConsumerState<TankFormSheet> {
  late final TextEditingController nameCtrl;
  late final TextEditingController capacityCtrl;
  late final TextEditingController thresholdCtrl;
  late String fuelType;
  late bool active;
  bool submitting = false;
  String? err;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    nameCtrl = TextEditingController(text: e?['name'] as String? ?? '');
    capacityCtrl =
        TextEditingController(text: (e?['capacity_liters'] ?? '').toString());
    thresholdCtrl = TextEditingController(
        text: (e?['low_stock_threshold'] ?? '500').toString());
    fuelType = e?['fuel_type'] as String? ?? FuelTypes.all.first;
    active = e?['active'] as bool? ?? true;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    capacityCtrl.dispose();
    thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (nameCtrl.text.trim().isEmpty) {
      setState(() => err = 'Name is required');
      return;
    }
    final cap = double.tryParse(capacityCtrl.text) ?? 0;
    if (cap <= 0) {
      setState(() => err = 'Enter valid capacity');
      return;
    }

    setState(() {
      submitting = true;
      err = null;
    });

    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final payload = {
        'station_id': user.stationId,
        'name': nameCtrl.text.trim(),
        'fuel_type': fuelType,
        'capacity_liters': cap,
        'low_stock_threshold': double.tryParse(thresholdCtrl.text) ?? 500,
        'active': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (widget.existing != null) {
        await db.from('Tank').update(payload).eq('id', widget.existing!['id']);
      } else {
        await db.from('Tank').insert({
          ...payload,
          'id': const Uuid().v4(),
        });
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(isEdit ? Icons.edit_outlined : Icons.add_circle_outline,
                  color: AppColors.blue, size: 22),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(isEdit ? 'Edit Tank' : 'Add Tank',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700))),
              IconButton(
                  icon: const Icon(Icons.close,
                      size: 20, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 20),
            _Field(label: 'Tank Name (e.g. Tank 1)', ctrl: nameCtrl),
            const SizedBox(height: 16),
            const Text('Fuel Type',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: FuelTypes.all.map((type) {
                final sel = fuelType == type;
                return ChoiceChip(
                  label: Text(type),
                  selected: sel,
                  onSelected: (s) => setState(() => fuelType = type),
                  selectedColor: AppColors.blue.withOpacity(0.1),
                  labelStyle: TextStyle(
                      color: sel ? AppColors.blue : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                  child: _Field(
                      label: 'Capacity (L)',
                      ctrl: capacityCtrl,
                      keyboard: const TextInputType.numberWithOptions(
                          decimal: true))),
              const SizedBox(width: 12),
              Expanded(
                  child: _Field(
                      label: 'Low Threshold (L)',
                      ctrl: thresholdCtrl,
                      keyboard: const TextInputType.numberWithOptions(
                          decimal: true))),
            ]),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Active',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: const Text('Visible in shifts and inventory',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              value: active,
              onChanged: (v) => setState(() => active = v),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.blue,
            ),
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(err!,
                    style: const TextStyle(color: AppColors.red, fontSize: 12)),
              ),
            const SizedBox(height: 24),
            AppButton(
              label: isEdit ? 'Update Tank' : 'Create Tank',
              loading: submitting,
              onTap: _submit,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final TextInputType? keyboard;
  const _Field({required this.label, required this.ctrl, this.keyboard});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }
}

class PumpFormSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  const PumpFormSheet({super.key, this.existing});
  @override
  ConsumerState<PumpFormSheet> createState() => _PumpFormSheetState();
}

class _PumpFormSheetState extends ConsumerState<PumpFormSheet> {
  late final TextEditingController nameCtrl;
  late String providerType;
  late bool active;
  bool submitting = false;
  String? err;

  static const _providers = [
    'PHONEPE',
    'PAYTM',
    'BHARATPE',
    'RAZORPAY',
    'MANUAL',
    'NONE'
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    nameCtrl = TextEditingController(text: e?['name'] as String? ?? '');
    providerType = e?['provider_type'] as String? ?? 'NONE';
    active = e?['active'] as bool? ?? true;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (nameCtrl.text.trim().isEmpty) {
      setState(() => err = 'Name is required');
      return;
    }

    setState(() {
      submitting = true;
      err = null;
    });

    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final payload = {
        'station_id': user.stationId,
        'name': nameCtrl.text.trim(),
        'provider_type': providerType,
        'active': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (widget.existing != null) {
        await db.from('Pump').update(payload).eq('id', widget.existing!['id']);
      } else {
        await db.from('Pump').insert({
          ...payload,
          'id': const Uuid().v4(),
        });
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(isEdit ? Icons.edit_outlined : Icons.add_circle_outline,
                  color: AppColors.blue, size: 22),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(isEdit ? 'Edit Pump' : 'Add Pump',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700))),
              IconButton(
                  icon: const Icon(Icons.close,
                      size: 20, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 20),
            _Field(label: 'Pump Name (e.g. Pump 1)', ctrl: nameCtrl),
            const SizedBox(height: 16),
            const Text('Provider Type',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: providerType,
              items: _providers
                  .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p,
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textPrimary))))
                  .toList(),
              onChanged: (v) => setState(() => providerType = v!),
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                filled: true,
                fillColor: AppColors.bgSurface,
              ),
              dropdownColor: AppColors.bgCard,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Active',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              subtitle: const Text('Visible in shifts',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              value: active,
              onChanged: (v) => setState(() => active = v),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.blue,
            ),
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(err!,
                    style: const TextStyle(color: AppColors.red, fontSize: 12)),
              ),
            const SizedBox(height: 24),
            AppButton(
              label: isEdit ? 'Update Pump' : 'Create Pump',
              loading: submitting,
              onTap: _submit,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}

class NozzleFormSheet extends ConsumerStatefulWidget {
  final String pumpId;
  final Map<String, dynamic>? existing;
  const NozzleFormSheet({super.key, required this.pumpId, this.existing});
  @override
  ConsumerState<NozzleFormSheet> createState() => _NozzleFormSheetState();
}

class _NozzleFormSheetState extends ConsumerState<NozzleFormSheet> {
  late final TextEditingController labelCtrl;
  late final TextEditingController testingCtrl;
  late String fuelType;
  late bool active;
  String? tankId;
  List<dynamic> _tanks = [];
  bool _loadingTanks = true;
  bool submitting = false;
  String? err;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    labelCtrl = TextEditingController(text: e?['label'] as String? ?? '');
    testingCtrl =
        TextEditingController(text: (e?['default_testing'] ?? '0').toString());
    fuelType = e?['fuel_type'] as String? ?? FuelTypes.all.first;
    active = e?['active'] as bool? ?? true;
    tankId = e?['tank_id'] as String?;
    _fetchTanks();
  }

  @override
  void dispose() {
    labelCtrl.dispose();
    testingCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchTanks() async {
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final data = await db
          .from('Tank')
          .select('id, name')
          .eq('station_id', user.stationId)
          .eq('active', true)
          .order('name');
      setState(() {
        _tanks = data as List;
        if (tankId == null && _tanks.isNotEmpty) {
          tankId = _tanks.first['id'] as String;
        }
        _loadingTanks = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          err = 'Failed to load tanks: $e';
          _loadingTanks = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (labelCtrl.text.trim().isEmpty) {
      setState(() => err = 'Label is required');
      return;
    }
    if (tankId == null) {
      setState(() => err = 'Tank must be selected');
      return;
    }

    setState(() {
      submitting = true;
      err = null;
    });

    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final payload = {
        'station_id': user.stationId,
        'pump_id': widget.pumpId,
        'tank_id': tankId,
        'label': labelCtrl.text.trim(),
        'fuel_type': fuelType,
        'default_testing': double.tryParse(testingCtrl.text) ?? 0,
        'active': active,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (widget.existing != null) {
        await db.from('Nozzle').update(payload).eq('id', widget.existing!['id']);
      } else {
        await db.from('Nozzle').insert({
          ...payload,
          'id': const Uuid().v4(),
        });
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => err = e.toString());
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(isEdit ? Icons.edit_outlined : Icons.add_circle_outline,
                  color: AppColors.blue, size: 22),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(isEdit ? 'Edit Nozzle' : 'Add Nozzle',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700))),
              IconButton(
                  icon: const Icon(Icons.close,
                      size: 20, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 20),
            _Field(label: 'Nozzle Label (e.g. N1)', ctrl: labelCtrl),
            const SizedBox(height: 16),
            const Text('Fuel Type',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: FuelTypes.all.map((type) {
                final sel = fuelType == type;
                return ChoiceChip(
                  label: Text(type),
                  selected: sel,
                  onSelected: (s) => setState(() => fuelType = type),
                  selectedColor: AppColors.blue.withOpacity(0.1),
                  labelStyle: TextStyle(
                      color: sel ? AppColors.blue : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (_loadingTanks)
              const LinearProgressIndicator()
            else if (_tanks.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Row(children: [
                  Icon(Icons.warning_amber, color: AppColors.amber, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('No active tanks found. Please add a tank first.',
                        style: TextStyle(color: AppColors.amber, fontSize: 12)),
                  ),
                ]),
              )
            else ...[
              const Text('Source Tank',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: tankId,
                items: _tanks
                    .map((t) => DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(t['name'] as String,
                            style: const TextStyle(
                                fontSize: 14, color: AppColors.textPrimary))))
                    .toList(),
                onChanged: (v) => setState(() => tankId = v!),
                decoration: InputDecoration(
                  border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  filled: true,
                  fillColor: AppColors.bgSurface,
                ),
                dropdownColor: AppColors.bgCard,
              ),
            ],
            const SizedBox(height: 16),
            _Field(
                label: 'Default Testing (L)',
                ctrl: testingCtrl,
                keyboard: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Active',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              value: active,
              onChanged: (v) => setState(() => active = v),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.blue,
            ),
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(err!,
                    style: const TextStyle(color: AppColors.red, fontSize: 12)),
              ),
            const SizedBox(height: 24),
            AppButton(
              label: isEdit ? 'Update Nozzle' : 'Create Nozzle',
              loading: submitting,
              onTap: (_tanks.isEmpty || submitting) ? null : _submit,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}
