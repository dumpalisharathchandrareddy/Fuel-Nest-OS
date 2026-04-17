// All models match the real Prisma schema exactly.
// Column names taken directly from schema.prisma — zero guessing.

double _d(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

int _i(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '0') ?? 0;

// ─── Shift ────────────────────────────────────────────────────────────────────
// schema: id, station_id, pump_id, assigned_user_id, shift_label?,
//   status, rate_confirmed, confirmed_rate_id?, handover_note?,
//   start_time, submitted_at?, closed_at?, business_date?, created_at
// NO sale_amount on Shift — computed from NozzleEntry rows.

class Shift {
  final String id;
  final String stationId;
  final String pumpId;
  final String assignedUserId;
  final String? shiftLabel;
  final String status;
  final bool rateConfirmed;
  final String? handoverNote;
  final DateTime startTime;
  final DateTime? submittedAt;
  final DateTime? closedAt;
  final String? businessDate;
  final DateTime createdAt;
  // joined
  final String? pumpName;
  final String? assignedWorkerName;
  final List<NozzleEntry> nozzleEntries;
  final PaymentRecord? paymentRecord;

  const Shift({
    required this.id,
    required this.stationId,
    required this.pumpId,
    required this.assignedUserId,
    this.shiftLabel,
    required this.status,
    this.rateConfirmed = false,
    this.handoverNote,
    required this.startTime,
    this.submittedAt,
    this.closedAt,
    this.businessDate,
    required this.createdAt,
    this.pumpName,
    this.assignedWorkerName,
    this.nozzleEntries = const [],
    this.paymentRecord,
  });

  bool get isOpen => status == 'OPEN';
  bool get isSubmitted => status == 'SUBMITTED';
  bool get isClosed => status == 'CLOSED' || status == 'SETTLED';
  bool get isSettled => status == 'SETTLED';

  /// Computed — Shift has no sale_amount column.
  double get totalSaleAmount =>
      nozzleEntries.fold(0, (s, e) => s + e.saleAmount);
  double get totalSaleLitres =>
      nozzleEntries.fold(0, (s, e) => s + e.saleLitres);

  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        pumpId: j['pump_id'] as String,
        assignedUserId: j['assigned_user_id'] as String? ?? '',
        shiftLabel: j['shift_label'] as String?,
        status: j['status'] as String? ?? 'OPEN',
        rateConfirmed: j['rate_confirmed'] as bool? ?? false,
        handoverNote: j['handover_note'] as String?,
        startTime: DateTime.parse(
            j['start_time'] as String? ?? j['created_at'] as String),
        submittedAt: j['submitted_at'] != null
            ? DateTime.parse(j['submitted_at'] as String)
            : null,
        closedAt: j['closed_at'] != null
            ? DateTime.parse(j['closed_at'] as String)
            : null,
        businessDate: j['business_date'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        pumpName:
            (j['pump'] as Map<String, dynamic>?)?['name'] as String?,
        assignedWorkerName: (j['assigned_worker'] as Map<String, dynamic>?)?['full_name']
            as String?,
        nozzleEntries: (j['nozzle_entries'] as List<dynamic>? ?? [])
            .map((e) => NozzleEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        paymentRecord: j['payment_record'] != null
            ? PaymentRecord.fromJson(
                j['payment_record'] as Map<String, dynamic>)
            : null,
      );
}

// ─── NozzleEntry ──────────────────────────────────────────────────────────────
// schema: id, station_id, shift_id, nozzle_id, opening_reading,
//   closing_reading?, testing_quantity, testing_override_reason?,
//   opening_override_reason?, sale_litres?, rate, sale_amount?,
//   created_at, updated_at

class NozzleEntry {
  final String id;
  final String stationId;
  final String shiftId;
  final String nozzleId;
  final double openingReading;
  final double? closingReading;
  final double testingQuantity;
  final double saleLitres;
  final double rate;
  final double saleAmount;
  // joined
  final String? nozzleLabel;
  final String? fuelType;

  const NozzleEntry({
    required this.id,
    required this.stationId,
    required this.shiftId,
    required this.nozzleId,
    required this.openingReading,
    this.closingReading,
    this.testingQuantity = 0,
    this.saleLitres = 0,
    this.rate = 0,
    this.saleAmount = 0,
    this.nozzleLabel,
    this.fuelType,
  });

  bool get hasClosingReading => closingReading != null;

  factory NozzleEntry.fromJson(Map<String, dynamic> j) {
    final nozzle = j['nozzle'] as Map<String, dynamic>?;
    return NozzleEntry(
      id: j['id'] as String,
      stationId: j['station_id'] as String? ?? '',
      shiftId: j['shift_id'] as String? ?? '',
      nozzleId: j['nozzle_id'] as String,
      openingReading: _d(j['opening_reading']),
      closingReading:
          j['closing_reading'] != null ? _d(j['closing_reading']) : null,
      testingQuantity: _d(j['testing_quantity']),
      saleLitres: _d(j['sale_litres']),
      rate: _d(j['rate']),
      saleAmount: _d(j['sale_amount']),
      nozzleLabel: nozzle?['label'] as String?,
      fuelType: nozzle?['fuel_type'] as String?,
    );
  }
}

// ─── Tank ─────────────────────────────────────────────────────────────────────
// schema: id, station_id, name, fuel_type, capacity_liters,
//   active, created_at, updated_at, low_stock_threshold
// NO current_stock column — stock is computed from StockTransaction ledger.

class Tank {
  final String id;
  final String stationId;
  final String name;
  final String fuelType;
  final double capacityLiters;
  final bool active;
  final double lowStockThreshold;
  // computed at query time — NOT from DB column
  final double computedStock;

  const Tank({
    required this.id,
    required this.stationId,
    required this.name,
    required this.fuelType,
    required this.capacityLiters,
    required this.active,
    this.lowStockThreshold = 500,
    this.computedStock = 0,
  });

  double get fillPercentage =>
      capacityLiters > 0
          ? (computedStock / capacityLiters * 100).clamp(0, 100)
          : 0;

  bool get isLow => computedStock <= lowStockThreshold;
  bool get isCritical => fillPercentage < 10;

  factory Tank.fromJson(Map<String, dynamic> j, {double computedStock = 0}) =>
      Tank(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        name: j['name'] as String,
        fuelType: j['fuel_type'] as String,
        capacityLiters: _d(j['capacity_liters']),
        active: j['active'] as bool? ?? true,
        lowStockThreshold: _d(j['low_stock_threshold']),
        computedStock: computedStock,
      );
}

// ─── Pump ─────────────────────────────────────────────────────────────────────

class Pump {
  final String id;
  final String stationId;
  final String name;
  final String providerType;
  final bool active;
  final List<Nozzle> nozzles;

  const Pump({
    required this.id,
    required this.stationId,
    required this.name,
    this.providerType = 'NONE',
    required this.active,
    this.nozzles = const [],
  });

  factory Pump.fromJson(Map<String, dynamic> j) => Pump(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        name: j['name'] as String,
        providerType: j['provider_type'] as String? ?? 'NONE',
        active: j['active'] as bool? ?? true,
        nozzles: (j['nozzles'] as List<dynamic>? ?? [])
            .map((e) => Nozzle.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ─── Nozzle ───────────────────────────────────────────────────────────────────
// schema: id, station_id, pump_id, tank_id, label, fuel_type,
//   default_testing, active, created_at, updated_at

class Nozzle {
  final String id;
  final String stationId;
  final String pumpId;
  final String tankId;
  final String label;
  final String fuelType;
  final double defaultTesting;
  final bool active;

  const Nozzle({
    required this.id,
    required this.stationId,
    required this.pumpId,
    required this.tankId,
    required this.label,
    required this.fuelType,
    this.defaultTesting = 0,
    required this.active,
  });

  factory Nozzle.fromJson(Map<String, dynamic> j) => Nozzle(
        id: j['id'] as String,
        stationId: j['station_id'] as String? ?? '',
        pumpId: j['pump_id'] as String,
        tankId: j['tank_id'] as String? ?? '',
        label: j['label'] as String,
        fuelType: j['fuel_type'] as String,
        defaultTesting: _d(j['default_testing']),
        active: j['active'] as bool? ?? true,
      );
}

// ─── FuelRate ─────────────────────────────────────────────────────────────────
// schema: id, station_id, fuel_type, rate, set_by_id,
//   effective_from, created_at
// NO is_active — active rate = latest effective_from per fuel_type

class FuelRate {
  final String id;
  final String stationId;
  final String fuelType;
  final double rate;
  final String setById;
  final DateTime effectiveFrom;
  final DateTime createdAt;

  const FuelRate({
    required this.id,
    required this.stationId,
    required this.fuelType,
    required this.rate,
    required this.setById,
    required this.effectiveFrom,
    required this.createdAt,
  });

  factory FuelRate.fromJson(Map<String, dynamic> j) => FuelRate(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        fuelType: j['fuel_type'] as String,
        rate: _d(j['rate']),
        setById: j['set_by_id'] as String? ?? '',
        effectiveFrom: DateTime.parse(j['effective_from'] as String),
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ─── PaymentRecord ────────────────────────────────────────────────────────────
// schema: id, station_id, shift_id, pump_id,
//   upi_amount, upi_source?, upi_fetched_at?,
//   card_amount, credit_amount, cash_to_collect,
//   actual_cash_collected_amount?, cash_collected, cash_collected_at?,
//   total_sale_amount, is_balanced, mismatch_amount,
//   mismatch_resolution_note?, mismatch_resolved_by_id?,
//   created_at, updated_at
// ONE row per shift — not separate rows per payment method.

class PaymentRecord {
  final String id;
  final String stationId;
  final String shiftId;
  final String pumpId;
  final double upiAmount;
  final String? upiSource;
  final double cardAmount;
  final double creditAmount;
  final double cashToCollect;
  final double? actualCashCollectedAmount;
  final bool cashCollected;
  final double totalSaleAmount;
  final bool isBalanced;
  final double mismatchAmount;
  final String? mismatchResolutionNote;
  final DateTime createdAt;

  const PaymentRecord({
    required this.id,
    required this.stationId,
    required this.shiftId,
    required this.pumpId,
    this.upiAmount = 0,
    this.upiSource,
    this.cardAmount = 0,
    this.creditAmount = 0,
    this.cashToCollect = 0,
    this.actualCashCollectedAmount,
    this.cashCollected = false,
    this.totalSaleAmount = 0,
    this.isBalanced = false,
    this.mismatchAmount = 0,
    this.mismatchResolutionNote,
    required this.createdAt,
  });

  double get totalCollected =>
      upiAmount +
      cardAmount +
      creditAmount +
      (actualCashCollectedAmount ?? cashToCollect);

  factory PaymentRecord.fromJson(Map<String, dynamic> j) => PaymentRecord(
        id: j['id'] as String,
        stationId: j['station_id'] as String? ?? '',
        shiftId: j['shift_id'] as String,
        pumpId: j['pump_id'] as String? ?? '',
        upiAmount: _d(j['upi_amount']),
        upiSource: j['upi_source'] as String?,
        cardAmount: _d(j['card_amount']),
        creditAmount: _d(j['credit_amount']),
        cashToCollect: _d(j['cash_to_collect']),
        actualCashCollectedAmount: j['actual_cash_collected_amount'] != null
            ? _d(j['actual_cash_collected_amount'])
            : null,
        cashCollected: j['cash_collected'] as bool? ?? false,
        totalSaleAmount: _d(j['total_sale_amount']),
        isBalanced: j['is_balanced'] as bool? ?? false,
        mismatchAmount: _d(j['mismatch_amount']),
        mismatchResolutionNote: j['mismatch_resolution_note'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ─── CreditCustomer ───────────────────────────────────────────────────────────
// schema: id, station_id, full_name, phone_number, email?,
//   customer_code, active, created_by_id?, created_at, updated_at,
//   deleted_at?, advance_balance, is_walk_in
// NO credit_limit, NO vehicle_number — not in schema.

class CreditCustomer {
  final String id;
  final String stationId;
  final String fullName;
  final String phoneNumber;
  final String? email;
  final String customerCode;
  final bool active;
  final double advanceBalance;
  final bool isWalkIn;
  final DateTime? deletedAt;
  // computed: sum of open CreditTransaction amounts minus CreditPayment amounts
  final double outstandingBalance;

  const CreditCustomer({
    required this.id,
    required this.stationId,
    required this.fullName,
    required this.phoneNumber,
    this.email,
    required this.customerCode,
    required this.active,
    this.advanceBalance = 0,
    this.isWalkIn = false,
    this.deletedAt,
    this.outstandingBalance = 0,
  });

  bool get isDeleted => deletedAt != null;

  factory CreditCustomer.fromJson(Map<String, dynamic> j,
          {double outstandingBalance = 0}) =>
      CreditCustomer(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        fullName: j['full_name'] as String,
        phoneNumber: j['phone_number'] as String,
        email: j['email'] as String?,
        customerCode: j['customer_code'] as String? ?? '',
        active: j['active'] as bool? ?? true,
        advanceBalance: _d(j['advance_balance']),
        isWalkIn: j['is_walk_in'] as bool? ?? false,
        deletedAt: j['deleted_at'] != null
            ? DateTime.parse(j['deleted_at'] as String)
            : null,
        outstandingBalance: outstandingBalance,
      );
}

// ─── CreditTransaction ────────────────────────────────────────────────────────
// schema: id, station_id, customer_id, pump_id?, shift_id?, date,
//   amount, liters?, fuel_type?, remaining_balance, status,
//   created_by_id, created_at, updated_at, business_date?

class CreditTransaction {
  final String id;
  final String stationId;
  final String customerId;
  final String? pumpId;
  final String? shiftId;
  final DateTime date;
  final double amount;
  final double? liters;
  final String? fuelType;
  final double remainingBalance;
  final String status;
  final String createdById;
  final DateTime createdAt;
  final String? businessDate;
  // joined
  final String? customerName;

  const CreditTransaction({
    required this.id,
    required this.stationId,
    required this.customerId,
    this.pumpId,
    this.shiftId,
    required this.date,
    required this.amount,
    this.liters,
    this.fuelType,
    required this.remainingBalance,
    this.status = 'PENDING',
    required this.createdById,
    required this.createdAt,
    this.businessDate,
    this.customerName,
  });

  factory CreditTransaction.fromJson(Map<String, dynamic> j) =>
      CreditTransaction(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        customerId: j['customer_id'] as String,
        pumpId: j['pump_id'] as String?,
        shiftId: j['shift_id'] as String?,
        date: DateTime.parse(j['date'] as String),
        amount: _d(j['amount']),
        liters: j['liters'] != null ? _d(j['liters']) : null,
        fuelType: j['fuel_type'] as String?,
        remainingBalance: _d(j['remaining_balance']),
        status: j['status'] as String? ?? 'PENDING',
        createdById: j['created_by_id'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        businessDate: j['business_date'] as String?,
        customerName:
            (j['customer'] as Map<String, dynamic>?)?['full_name'] as String?,
      );
}

// ─── CreditPayment ────────────────────────────────────────────────────────────
// schema: id, station_id, credit_id (→ CreditTransaction.id),
//   paid_amount, payment_mode, date, note?, recorded_by_id,
//   idempotency_key?, created_at, business_date?
// To find payments for a customer: join through CreditTransaction on customer_id.

class CreditPayment {
  final String id;
  final String stationId;
  final String creditId;       // CreditTransaction.id — NOT customer_id
  final double paidAmount;     // NOT amount
  final String paymentMode;    // NOT payment_method
  final DateTime date;
  final String? note;
  final String recordedById;
  final DateTime createdAt;
  final String? businessDate;
  // joined via credit → customer
  final String? customerId;
  final String? customerName;

  const CreditPayment({
    required this.id,
    required this.stationId,
    required this.creditId,
    required this.paidAmount,
    required this.paymentMode,
    required this.date,
    this.note,
    required this.recordedById,
    required this.createdAt,
    this.businessDate,
    this.customerId,
    this.customerName,
  });

  factory CreditPayment.fromJson(Map<String, dynamic> j) => CreditPayment(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        creditId: j['credit_id'] as String,
        paidAmount: _d(j['paid_amount']),
        paymentMode: j['payment_mode'] as String,
        date: DateTime.parse(j['date'] as String),
        note: j['note'] as String?,
        recordedById: j['recorded_by_id'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        businessDate: j['business_date'] as String?,
        customerId: (j['credit'] as Map<String, dynamic>?)?['customer_id']
            as String?,
        customerName:
            ((j['credit'] as Map<String, dynamic>?)?['customer']
                    as Map<String, dynamic>?)?['full_name'] as String?,
      );
}

// ─── StaffMember (User) ───────────────────────────────────────────────────────

class StaffMember {
  final String id;
  final String stationId;
  final String fullName;
  final String role;
  final String? employeeId;
  final String phoneNumber;
  final String username;
  final bool active;
  final DateTime createdAt;
  final double? baseMonthlySalary;

  const StaffMember({
    required this.id,
    required this.stationId,
    required this.fullName,
    required this.role,
    this.employeeId,
    required this.phoneNumber,
    required this.username,
    required this.active,
    required this.createdAt,
    this.baseMonthlySalary,
  });

  String get displayRole => switch (role) {
        'MANAGER' => 'Manager',
        'PUMP_PERSON' => 'Staff',
        'DEALER' => 'Dealer',
        _ => role,
      };

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        fullName: j['full_name'] as String,
        role: j['role'] as String,
        employeeId: j['employee_id'] as String?,
        phoneNumber: j['phone_number'] as String? ?? '',
        username: j['username'] as String? ?? '',
        active: j['active'] as bool? ?? true,
        createdAt: DateTime.parse(j['created_at'] as String),
        baseMonthlySalary:
            (j['salary_config'] as Map<String, dynamic>?) != null
                ? _d((j['salary_config'] as Map<String, dynamic>)[
                    'base_monthly_salary'])
                : null,
      );
}

// ─── SalaryPayout ─────────────────────────────────────────────────────────────
// schema: id, station_id, user_id, month, year, period_label?,
//   base_salary_snapshot, total_advances_deducted, other_deductions,
//   incentives, net_paid, status, generated_by_id, paid_by_id?,
//   created_at, updated_at
// NOT: staff_id, net_pay, base_salary, bonus, penalty, period_month, period_year

class SalaryPayout {
  final String id;
  final String stationId;
  final String userId;
  final int month;
  final int year;
  final String? periodLabel;
  final double baseSalarySnapshot;
  final double totalAdvancesDeducted;
  final double otherDeductions;
  final double incentives;
  final double netPaid;
  final String status;
  final String generatedById;
  final String? paidById;
  final DateTime createdAt;
  // joined
  final String? staffName;
  final String? staffRole;

  const SalaryPayout({
    required this.id,
    required this.stationId,
    required this.userId,
    required this.month,
    required this.year,
    this.periodLabel,
    required this.baseSalarySnapshot,
    this.totalAdvancesDeducted = 0,
    this.otherDeductions = 0,
    this.incentives = 0,
    required this.netPaid,
    this.status = 'PROCESSED',
    required this.generatedById,
    this.paidById,
    required this.createdAt,
    this.staffName,
    this.staffRole,
  });

  factory SalaryPayout.fromJson(Map<String, dynamic> j) => SalaryPayout(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        userId: j['user_id'] as String,
        month: _i(j['month']),
        year: _i(j['year']),
        periodLabel: j['period_label'] as String?,
        baseSalarySnapshot: _d(j['base_salary_snapshot']),
        totalAdvancesDeducted: _d(j['total_advances_deducted']),
        otherDeductions: _d(j['other_deductions']),
        incentives: _d(j['incentives']),
        netPaid: _d(j['net_paid']),
        status: j['status'] as String? ?? 'PROCESSED',
        generatedById: j['generated_by_id'] as String? ?? '',
        paidById: j['paid_by_id'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        staffName:
            (j['user'] as Map<String, dynamic>?)?['full_name'] as String?,
        staffRole:
            (j['user'] as Map<String, dynamic>?)?['role'] as String?,
      );
}

// ─── StaffAdvance ─────────────────────────────────────────────────────────────
// schema: id, station_id, user_id, amount, date, status,
//   reference_shift_id?, note?, recorded_by_id, created_at, updated_at,
//   payout_id?, reason?, issued_by_id?, pay_period_label?,
//   is_voided, voided_by_id?, voided_at?, void_reason?

class StaffAdvance {
  final String id;
  final String stationId;
  final String userId;
  final double amount;
  final DateTime date;
  final String status;
  final String? note;
  final String? reason;
  final String recordedById;
  final String? payoutId;
  final String? payPeriodLabel;
  final bool isVoided;
  final DateTime createdAt;

  const StaffAdvance({
    required this.id,
    required this.stationId,
    required this.userId,
    required this.amount,
    required this.date,
    this.status = 'PENDING',
    this.note,
    this.reason,
    required this.recordedById,
    this.payoutId,
    this.payPeriodLabel,
    this.isVoided = false,
    required this.createdAt,
  });

  factory StaffAdvance.fromJson(Map<String, dynamic> j) => StaffAdvance(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        userId: j['user_id'] as String,
        amount: _d(j['amount']),
        date: DateTime.parse(j['date'] as String),
        status: j['status'] as String? ?? 'PENDING',
        note: j['note'] as String?,
        reason: j['reason'] as String?,
        recordedById: j['recorded_by_id'] as String? ?? '',
        payoutId: j['payout_id'] as String?,
        payPeriodLabel: j['pay_period_label'] as String?,
        isVoided: j['is_voided'] as bool? ?? false,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ─── DailyExpense ─────────────────────────────────────────────────────────────
// schema: id, station_id, expense_date (DateTime), recorded_at,
//   name, category, custom_category?, amount, description?,
//   vendor_name?, receipt_url?, recorded_by (direct user_id reference),
//   is_system_generated, deleted_at?, deleted_by_id?,
//   created_at, updated_at, business_date?
// NOTE: recorded_by is the column name (not recorded_by_id).

class DailyExpense {
  final String id;
  final String stationId;
  final DateTime expenseDate;
  final DateTime recordedAt;
  final String name;
  final String category;
  final String? customCategory;
  final double amount;
  final String? description;
  final String? vendorName;
  final String recordedBy;  // user_id — column is literally "recorded_by"
  final bool isSystemGenerated;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final String? businessDate;

  const DailyExpense({
    required this.id,
    required this.stationId,
    required this.expenseDate,
    required this.recordedAt,
    required this.name,
    required this.category,
    this.customCategory,
    required this.amount,
    this.description,
    this.vendorName,
    required this.recordedBy,
    this.isSystemGenerated = false,
    this.deletedAt,
    required this.createdAt,
    this.businessDate,
  });

  bool get isDeleted => deletedAt != null;

  factory DailyExpense.fromJson(Map<String, dynamic> j) => DailyExpense(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        expenseDate: DateTime.parse(j['expense_date'] as String),
        recordedAt: DateTime.parse(
            j['recorded_at'] as String? ?? j['created_at'] as String),
        name: j['name'] as String,
        category: j['category'] as String,
        customCategory: j['custom_category'] as String?,
        amount: _d(j['amount']),
        description: j['description'] as String?,
        vendorName: j['vendor_name'] as String?,
        recordedBy: j['recorded_by'] as String? ?? '',
        isSystemGenerated: j['is_system_generated'] as bool? ?? false,
        deletedAt: j['deleted_at'] != null
            ? DateTime.parse(j['deleted_at'] as String)
            : null,
        createdAt: DateTime.parse(j['created_at'] as String),
        businessDate: j['business_date'] as String?,
      );
}

// ─── FuelOrder ────────────────────────────────────────────────────────────────
// schema: id, station_id, invoice_no, vendor, date, total_amount,
//   status, created_by_id, created_at, updated_at, total_liters,
//   payment_mode, cheque_reference?, notes?, linked_cheque_id?
// NO fuel_type, quantity, delivery_date, supplier_name on this model.

class FuelOrder {
  final String id;
  final String stationId;
  final String invoiceNo;
  final String vendor;
  final DateTime date;
  final double totalAmount;
  final String status;
  final double totalLiters;
  final String paymentMode;
  final String? chequeReference;
  final String? notes;
  final String? linkedChequeId;
  final String createdById;
  final DateTime createdAt;

  const FuelOrder({
    required this.id,
    required this.stationId,
    required this.invoiceNo,
    required this.vendor,
    required this.date,
    required this.totalAmount,
    this.status = 'DRAFT',
    this.totalLiters = 0,
    this.paymentMode = 'CASH',
    this.chequeReference,
    this.notes,
    this.linkedChequeId,
    required this.createdById,
    required this.createdAt,
  });

  factory FuelOrder.fromJson(Map<String, dynamic> j) => FuelOrder(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        invoiceNo: j['invoice_no'] as String? ?? '',
        vendor: j['vendor'] as String,
        date: DateTime.parse(j['date'] as String),
        totalAmount: _d(j['total_amount']),
        status: j['status'] as String? ?? 'DRAFT',
        totalLiters: _d(j['total_liters']),
        paymentMode: j['payment_mode'] as String? ?? 'CASH',
        chequeReference: j['cheque_reference'] as String?,
        notes: j['notes'] as String?,
        linkedChequeId: j['linked_cheque_id'] as String?,
        createdById: j['created_by_id'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ─── InventoryCheque ──────────────────────────────────────────────────────────
// schema: id, station_id, vendor, amount, cheque_reference,
//   payment_date, status, notes?, created_by_id, created_at, updated_at
// NOT: cheque_number, due_date, supplier_name, bank_name

class InventoryCheque {
  final String id;
  final String stationId;
  final String vendor;
  final double amount;
  final String chequeReference;
  final DateTime paymentDate;
  final String status;
  final String? notes;
  final String createdById;
  final DateTime createdAt;

  const InventoryCheque({
    required this.id,
    required this.stationId,
    required this.vendor,
    required this.amount,
    required this.chequeReference,
    required this.paymentDate,
    this.status = 'ISSUED',
    this.notes,
    required this.createdById,
    required this.createdAt,
  });

  factory InventoryCheque.fromJson(Map<String, dynamic> j) => InventoryCheque(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        vendor: j['vendor'] as String,
        amount: _d(j['amount']),
        chequeReference: j['cheque_reference'] as String,
        paymentDate: DateTime.parse(j['payment_date'] as String),
        status: j['status'] as String? ?? 'ISSUED',
        notes: j['notes'] as String?,
        createdById: j['created_by_id'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ─── DipReading ───────────────────────────────────────────────────────────────
// schema: id, station_id, tank_id, reading_mm?, calculated_volume,
//   variation_liters?, captured_at, captured_by_id, created_at
// NOT: reading_value, recorded_by

class DipReading {
  final String id;
  final String stationId;
  final String tankId;
  final double? readingMm;
  final double calculatedVolume;  // litres — the actual stock figure
  final double? variationLiters;
  final DateTime capturedAt;
  final String capturedById;
  final DateTime createdAt;

  const DipReading({
    required this.id,
    required this.stationId,
    required this.tankId,
    this.readingMm,
    required this.calculatedVolume,
    this.variationLiters,
    required this.capturedAt,
    required this.capturedById,
    required this.createdAt,
  });

  factory DipReading.fromJson(Map<String, dynamic> j) => DipReading(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        tankId: j['tank_id'] as String,
        readingMm:
            j['reading_mm'] != null ? _d(j['reading_mm']) : null,
        calculatedVolume: _d(j['calculated_volume']),
        variationLiters: j['variation_liters'] != null
            ? _d(j['variation_liters'])
            : null,
        capturedAt: DateTime.parse(j['captured_at'] as String),
        capturedById: j['captured_by_id'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ─── StockTransaction ─────────────────────────────────────────────────────────
// schema: id, station_id, tank_id, type, quantity, reference_id,
//   created_by_id?, created_at
// Used to compute current stock per tank. type: DELIVERY, SALE, ADJUSTMENT, etc.

class StockTransaction {
  final String id;
  final String stationId;
  final String tankId;
  final String type;
  final double quantity;
  final String referenceId;
  final String? createdById;
  final DateTime createdAt;

  const StockTransaction({
    required this.id,
    required this.stationId,
    required this.tankId,
    required this.type,
    required this.quantity,
    required this.referenceId,
    this.createdById,
    required this.createdAt,
  });

  factory StockTransaction.fromJson(Map<String, dynamic> j) => StockTransaction(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        tankId: j['tank_id'] as String,
        type: j['type'] as String,
        quantity: _d(j['quantity']),
        referenceId: j['reference_id'] as String? ?? '',
        createdById: j['created_by_id'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ─── TankInitialStock ─────────────────────────────────────────────────────────
// schema: id, station_id, tank_id, fuel_type, opening_litres,
//   stock_date, notes?, recorded_by_id, created_at, updated_at

class TankInitialStock {
  final String id;
  final String stationId;
  final String tankId;
  final String fuelType;
  final double openingLitres;
  final DateTime stockDate;
  final String? notes;
  final String recordedById;
  final DateTime createdAt;

  const TankInitialStock({
    required this.id,
    required this.stationId,
    required this.tankId,
    required this.fuelType,
    required this.openingLitres,
    required this.stockDate,
    this.notes,
    required this.recordedById,
    required this.createdAt,
  });

  factory TankInitialStock.fromJson(Map<String, dynamic> j) => TankInitialStock(
        id: j['id'] as String,
        stationId: j['station_id'] as String,
        tankId: j['tank_id'] as String,
        fuelType: j['fuel_type'] as String,
        openingLitres: _d(j['opening_litres']),
        stockDate: DateTime.parse(j['stock_date'] as String),
        notes: j['notes'] as String?,
        recordedById: j['recorded_by_id'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
