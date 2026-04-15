// hardware_config_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/widgets.dart';

class HardwareConfigScreen extends ConsumerStatefulWidget {
  const HardwareConfigScreen({super.key});
  @override
  ConsumerState<HardwareConfigScreen> createState() => _HardwareConfigScreenState();
}

class _HardwareConfigScreenState extends ConsumerState<HardwareConfigScreen> {
  bool _loading = true; String? _error;
  List<dynamic> _pumps = []; List<dynamic> _tanks = [];

  @override void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final results = await Future.wait([
        db.from('Pump').select('id, name, provider_type, active, nozzles:Nozzle(id, label, fuel_type, active)').eq('station_id', user.stationId),
        db.from('Tank').select('id, name, fuel_type, capacity_liters, active').eq('station_id', user.stationId),
      ]);
      setState(() { _pumps = results[0]; _tanks = results[1]; _loading = false; });
    } catch (e) { setState(() { _error = e.toString(); _loading = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.bgApp, body: LoadingView());
    if (_error != null) return Scaffold(backgroundColor: AppColors.bgApp, body: ErrorView(message: _error!, onRetry: _fetch));

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionHeader(title: 'Pumps & Nozzles'),
        const SizedBox(height: 12),
        ..._pumps.map((p) => Padding(padding: const EdgeInsets.only(bottom: 10), child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.local_gas_station, color: AppColors.blue, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(p['name'] as String? ?? '', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700))),
            StatusBadge(label: p['provider_type'] as String? ?? 'MANUAL', tone: BadgeTone.info),
            const SizedBox(width: 6),
            StatusBadge(label: p['active'] == true ? 'Active' : 'Inactive', tone: p['active'] == true ? BadgeTone.success : BadgeTone.error),
          ]),
          const SizedBox(height: 10),
          ...(p['nozzles'] as List? ?? []).map((n) => Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
            const SizedBox(width: 26),
            Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.textMuted, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text('${n['label']} — ${n['fuel_type']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
            StatusBadge(label: n['active'] == true ? 'On' : 'Off', tone: n['active'] == true ? BadgeTone.success : BadgeTone.error),
          ]))),
        ])))),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Tanks'),
        const SizedBox(height: 12),
        ..._tanks.map((t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: AppCard(child: Row(children: [
          const Icon(Icons.water, color: AppColors.blue, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t['name'] as String? ?? '', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
            Text('${t['fuel_type']} · ${t['capacity_liters']} L capacity', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ])),
          StatusBadge(label: t['active'] == true ? 'Active' : 'Inactive', tone: t['active'] == true ? BadgeTone.success : BadgeTone.error),
        ])))),
      ]),
    );
  }
}

// ─── fuel_rate_screen.dart ────────────────────────────────────────────────────

class FuelRateScreen extends ConsumerStatefulWidget {
  const FuelRateScreen({super.key});
  @override
  ConsumerState<FuelRateScreen> createState() => _FuelRateScreenState();
}

class _FuelRateScreenState extends ConsumerState<FuelRateScreen> {
  bool _loading = true; String? _error;
  List<dynamic> _rates = [];
  final Map<String, TextEditingController> _controllers = {};

  @override void initState() { super.initState(); _fetch(); }
  @override void dispose() { for (final c in _controllers.values) c.dispose(); super.dispose(); }

  Future<void> _fetch() async {
    setState(() { _loading = true; });
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      // Active rate = latest per fuel_type based on effective_from
      final allRates = await db.from('FuelRate')
          .select('id, fuel_type, rate, set_by_id, effective_from, created_at')
          .eq('station_id', user.stationId)
          .order('effective_from', ascending: false);

      // Deduplicate: keep latest per fuel_type
      final seen = <String>{};
      final rates = (allRates as List).where((r) {
        final ft = r['fuel_type'] as String;
        if (seen.contains(ft)) return false;
        seen.add(ft);
        return true;
      }).toList();
      for (final r in rates) _controllers[r['fuel_type'] as String] = TextEditingController(text: r['rate']?.toString() ?? '0');
      setState(() { _rates = rates; _loading = false; });
    } catch (e) { setState(() { _error = e.toString(); _loading = false; }); }
  }

  Future<void> _saveRate(String fuelType) async {
    final newRate = double.tryParse(_controllers[fuelType]?.text ?? '0') ?? 0;
    if (newRate <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid rate'))); return; }
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.from('FuelRate').insert({
        'station_id': user.stationId,
        'fuel_type': fuelType,
        'rate': newRate,
        'effective_from': now,
        'set_by_id': user.id,
        'created_at': now
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ $fuelType rate updated'), backgroundColor: AppColors.green));
      _fetch();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.bgApp, body: LoadingView());
    if (_error != null) return Scaffold(backgroundColor: AppColors.bgApp, body: ErrorView(message: _error!, onRetry: _fetch));

    return Scaffold(
      backgroundColor: AppColors.bgApp,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const AppCard(child: Row(children: [ Icon(Icons.info_outline, color: AppColors.blue, size: 16), SizedBox(width: 8), Expanded(child: Text('Rates shown per litre (₹/L). Changes take effect immediately for new shifts.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)))])),
        const SizedBox(height: 20),
        ..._rates.map((r) {
          final fuel = r['fuel_type'] as String;
          final fuelColor = switch (fuel) { 'Petrol' => AppColors.petrol, 'Diesel' => AppColors.diesel, 'Power' => AppColors.power, _ => AppColors.blue };
          return Padding(padding: const EdgeInsets.only(bottom: 12), child: AppCard(child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: fuelColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)), alignment: Alignment.center, child: Icon(Icons.local_gas_station, color: fuelColor, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Text(fuel, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600))),
            SizedBox(width: 100, child: TextFormField(
              controller: _controllers[fuel],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16),
              decoration: InputDecoration(
                prefixText: '₹', prefixStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.blue, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                filled: true, fillColor: AppColors.bgSurface,
              ),
            )),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.check_circle, color: AppColors.green, size: 22), onPressed: () => _saveRate(fuel), tooltip: 'Save Rate'),
          ])));
        }),
      ]),
    );
  }
}
