import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/tenant_service.dart';
import '../../../core/utils/ist_time.dart';
import '../../../shared/widgets/widgets.dart';

class FuelRateScreen extends ConsumerStatefulWidget {
  const FuelRateScreen({super.key});
  @override
  ConsumerState<FuelRateScreen> createState() => _FuelRateScreenState();
}

class _FuelRateScreenState extends ConsumerState<FuelRateScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _currentRates = [];
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _settings;
  final Map<String, TextEditingController> _controllers = {};
  
  bool get _isDealer => ref.read(currentUserProvider)?.isDealer ?? false;
  bool get _canEdit {
    if (_isDealer) return true;
    return _settings?['manager_can_edit_fuel_rates'] == true;
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;

      // 1. Fetch Station Settings
      final settings = await db
          .from('StationSettings')
          .select('manager_can_edit_fuel_rates')
          .eq('station_id', user.stationId)
          .maybeSingle();

      // 2. Fetch All Rates (for current and history)
      final results = await db
          .from('FuelRate')
          .select('id, fuel_type, rate, effective_from, set_by:User(id, full_name)')
          .eq('station_id', user.stationId)
          .order('effective_from', ascending: false);

      final rawRates = (results as List).map((e) => Map<String, dynamic>.from(e)).toList();

      // Calculate Current Rates (latest per type)
      final seenTypes = <String>{};
      final current = <Map<String, dynamic>>[];
      for (final r in rawRates) {
        final type = r['fuel_type'] as String;
        if (!seenTypes.contains(type)) {
          seenTypes.add(type);
          current.add(r);
          _controllers[type] = TextEditingController(text: r['rate']?.toString() ?? '0');
        }
      }

      setState(() {
        _settings = settings != null ? Map<String, dynamic>.from(settings) : null;
        _currentRates = current;
        _history = rawRates;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveRate(String fuelType) async {
    final newRate = double.tryParse(_controllers[fuelType]?.text ?? '0') ?? 0;
    if (newRate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid rate greater than 0')),
      );
      return;
    }

    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;
      final now = DateTime.now().toUtc().toIso8601String();

      await db.from('FuelRate').insert({
        'id': const Uuid().v4(),
        'station_id': user.stationId,
        'fuel_type': fuelType,
        'rate': newRate,
        'effective_from': now,
        'set_by_id': user.id,
        'created_at': now,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $fuelType rate updated successfully'),
            backgroundColor: AppColors.green,
          ),
        );
      }
      _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update rate: $e')),
        );
      }
    }
  }

  Future<void> _toggleManagerPermission(bool value) async {
    try {
      final db = TenantService.instance.client;
      final user = ref.read(currentUserProvider)!;

      await db
          .from('StationSettings')
          .update({'manager_can_edit_fuel_rates': value})
          .eq('station_id', user.stationId);

      _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update settings: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgApp,
      appBar: AppBar(
        title: const Text('Fuel Rates Management',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _fetch,
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(message: 'Loading rates...')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _fetch)
              : RefreshIndicator(
                  onRefresh: _fetch,
                  color: AppColors.blue,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildInfoCard(),
                      if (_isDealer) _buildSettingsCard(),
                      const SizedBox(height: 24),
                      _buildSectionHeader('Current Rates'),
                      const SizedBox(height: 12),
                      if (_currentRates.isEmpty)
                        const EmptyView(
                          title: 'No rates configured',
                          subtitle: 'Start by setting rates for your fuel types',
                          icon: Icons.currency_rupee,
                        )
                      else
                        ..._currentRates.map((r) => _buildRateCard(r)),
                      const SizedBox(height: 32),
                      _buildSectionHeader('Rate History'),
                      const SizedBox(height: 12),
                      if (_history.isEmpty)
                        const Center(
                            child: Text('No history available',
                                style: TextStyle(color: AppColors.textMuted)))
                      else
                        _buildHistoryTable(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _buildInfoCard() {
    return const AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.blue, size: 18),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Rates are per litre (₹/L). Updates take effect immediately for new shifts and will not affect currently open shifts.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard() {
    final enabled = _settings?['manager_can_edit_fuel_rates'] == true;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Manager Access',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  Text('Allow managers to update fuel rates',
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Switch.adaptive(
              value: enabled,
              onChanged: _toggleManagerPermission,
              activeColor: AppColors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildRateCard(Map<String, dynamic> rate) {
    final fuel = rate['fuel_type'] as String;
    final fuelColor = _getFuelColor(fuel);
    final canEdit = _canEdit;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: fuelColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.local_gas_station, color: fuelColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fuel,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                  Text(
                    'Last updated: ${IstTime.formatDate(DateTime.parse(rate['effective_from']))}',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextFormField(
                controller: _controllers[fuel],
                enabled: canEdit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                decoration: InputDecoration(
                  prefixText: '₹',
                  prefixStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  filled: true,
                  fillColor: canEdit ? AppColors.bgSurface : AppColors.bgCard.withOpacity(0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.blue, width: 2),
                  ),
                ),
              ),
            ),
            if (canEdit) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _saveRate(fuel),
                icon: const Icon(Icons.check_circle, color: AppColors.green, size: 28),
                tooltip: 'Update Rate',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTable() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('DATE', style: _historyHeaderStyle)),
                Expanded(flex: 2, child: Text('FUEL', style: _historyHeaderStyle)),
                Expanded(flex: 2, child: Text('RATE', style: _historyHeaderStyle)),
                Expanded(flex: 3, child: Text('SET BY', style: _historyHeaderStyle, textAlign: TextAlign.right)),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _history.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
            itemBuilder: (ctx, idx) {
              final h = _history[idx];
              final date = DateTime.parse(h['effective_from']);
              final fuel = h['fuel_type'] as String;
              final rate = h['rate']?.toString() ?? '0';
              final setter = (h['set_by'] as Map?)?['full_name'] ?? 'System';

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat('dd MMM').format(date),
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(DateFormat('hh:mm a').format(date),
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(fuel, style: TextStyle(color: _getFuelColor(fuel), fontWeight: FontWeight.w500, fontSize: 13)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text('₹$rate', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(setter as String, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), textAlign: TextAlign.right),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _getFuelColor(String type) {
    return switch (type) {
      'Petrol' => AppColors.petrol,
      'Diesel' => AppColors.diesel,
      'Power' => AppColors.power,
      _ => AppColors.blue
    };
  }

  static const _historyHeaderStyle = TextStyle(
    color: AppColors.textMuted,
    fontSize: 10,
    fontWeight: FontWeight.bold,
  );
}
