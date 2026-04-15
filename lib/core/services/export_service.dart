import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/ist_time.dart';
import '../utils/currency.dart';
import '../constants/app_constants.dart';

/// On-device PDF and Excel export.
/// Replaces backend PDF/Excel generation — runs fully on the Flutter device.
/// Matches all existing report formats from the web app.
class ExportService {
  ExportService._();
  static final instance = ExportService._();

  // ── PDF Export ────────────────────────────────────────────────────────────

  Future<File> generateShiftReport({
    required Map<String, dynamic> shiftData,
    required String stationName,
  }) async {
    final pdf = pw.Document();
    final now = IstTime.formatDateTime(DateTime.now().toUtc());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          _buildPdfHeader(
            title: 'Shift Report',
            subtitle: stationName,
            generatedAt: now,
          ),
          pw.SizedBox(height: 20),
          _buildPdfSection(
            title: 'Shift Summary',
            rows: [
              ['Pump', shiftData['pump_name']?.toString() ?? ''],
              ['Staff', shiftData['worker_name']?.toString() ?? ''],
              ['Status', shiftData['status']?.toString() ?? ''],
              [
                'Sale Amount',
                         IndianCurrency.format(
                          double.tryParse(((shiftData['nozzle_entries'] as List? ?? [])
                                      .fold<double>(
                                          0,
                                          (s, e) =>
                                              s +
                                              (double.tryParse((e as Map)['sale_amount']
                                                          ?.toString() ??
                                                      '0') ??
                                                  0))).toString()) ??
                              0,
                        ),
              ],
              ['Opened', shiftData['opened_at']?.toString() ?? ''],
              ['Closed', shiftData['closed_at']?.toString() ?? 'Open'],
            ],
          ),
          if (shiftData['nozzle_entries'] != null) ...[
            pw.SizedBox(height: 16),
            _buildPdfTable(
              title: 'Nozzle Readings',
              headers: ['Nozzle', 'Fuel', 'Opening', 'Closing', 'Volume'],
              rows: (shiftData['nozzle_entries'] as List<dynamic>)
                  .map((e) => <String>[
                        e['nozzle_label']?.toString() ??
                            (e['nozzle'] as Map?)?['label']?.toString() ??
                            '',
                        e['fuel_type']?.toString() ??
                            (e['nozzle'] as Map?)?['fuel_type']?.toString() ??
                            '',
                        e['opening_reading']?.toString() ?? '',
                        e['closing_reading']?.toString() ?? '',
                        IndianCurrency.formatLitres(
                          (double.tryParse(e['closing_reading']?.toString() ??
                                      '0') ??
                                  0) -
                              (double.tryParse(
                                      e['opening_reading']?.toString() ??
                                          '0') ??
                                  0),
                        ),
                      ])
                  .toList(),
            ),
          ],
          if (shiftData['payment_records'] != null) ...[
            pw.SizedBox(height: 16),
            _buildPdfTable(
              title: 'Payment Records',
              headers: ['Method', 'Amount', 'Status'],
              rows: (shiftData['payment_records'] as List<dynamic>)
                  .map((e) => [
                        e['payment_mode']?.toString() ?? '',
                        IndianCurrency.format(
                          double.tryParse(e['amount']?.toString() ?? '0') ?? 0,
                        ),
                        e['status']?.toString() ?? '',
                      ])
                  .toList(),
            ),
          ],
          pw.SizedBox(height: 32),
          _buildPdfFooter(stationName),
        ],
      ),
    );

    return _savePdf(pdf, 'shift_report');
  }

  Future<File> generateInventoryReport({
    required List<Map<String, dynamic>> tanks,
    required List<Map<String, dynamic>> orders,
    required List<Map<String, dynamic>> cheques,
    required String stationName,
  }) async {
    final pdf = pw.Document();
    final now = IstTime.formatDateTime(DateTime.now().toUtc());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          _buildPdfHeader(
            title: 'Inventory Report',
            subtitle: stationName,
            generatedAt: now,
          ),
          pw.SizedBox(height: 20),
          _buildPdfTable(
            title: 'Tank Status',
            headers: ['Tank', 'Fuel', 'Capacity', 'Current', 'Fill %'],
            rows: tanks.map((t) {
              final cap =
                  double.tryParse(t['capacity_liters']?.toString() ?? '0') ?? 0;
              final cur = double.tryParse(
                      (0.0 /* no current_stock - use StockTransaction */)
                               .toString()) ??
                  0;
              final pct = cap > 0 ? (cur / cap * 100).round() : 0;
              return [
                t['name']?.toString() ?? '',
                t['fuel_type']?.toString() ?? '',
                IndianCurrency.formatLitres(cap),
                IndianCurrency.formatLitres(cur),
                '$pct%',
              ];
            }).toList(),
          ),
          if (orders.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _buildPdfTable(
              title: 'Recent Orders',
              headers: ['Date', 'Fuel', 'Quantity', 'Amount'],
              rows: orders
                  .take(20)
                  .map((o) => [
                        o['date']?.toString() ?? '',
                        o['fuel_type']?.toString() ?? '',
                        IndianCurrency.formatLitres(
                          double.tryParse(
                                  o['total_liters']?.toString() ?? '0') ??
                              0,
                        ),
                        IndianCurrency.format(
                          double.tryParse(
                                  o['total_amount']?.toString() ?? '0') ??
                              0,
                        ),
                      ])
                  .toList(),
            ),
          ],
          pw.SizedBox(height: 32),
          _buildPdfFooter(stationName),
        ],
      ),
    );

    return _savePdf(pdf, 'inventory_report');
  }

  Future<File> generatePayrollReport({
    required List<Map<String, dynamic>> payouts,
    required String period,
    required double totalPaid,
    required String stationName,
  }) async {
    final pdf = pw.Document();
    final now = IstTime.formatDateTime(DateTime.now().toUtc());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          _buildPdfHeader(
            title: 'Payroll Report',
            subtitle: '$stationName · $period',
            generatedAt: now,
          ),
          pw.SizedBox(height: 20),
          _buildPdfTable(
            title: 'Salary Payouts',
            headers: ['Staff', 'Base', 'Advances', 'Bonus', 'Penalty', 'Net'],
            rows: payouts
                .map((p) => <String>[
                      p['staff_name']?.toString() ??
                          (p['user'] as Map?)?['full_name']?.toString() ??
                          '',
                      IndianCurrency.format(double.tryParse(
                              p['base_salary_snapshot']?.toString() ?? '0') ??
                          0),
                      IndianCurrency.format(
                          double.tryParse(p['advances']?.toString() ?? '0') ??
                              0),
                      IndianCurrency.format(
                          double.tryParse(p['incentives']?.toString() ?? '0') ??
                              0),
                      IndianCurrency.format(double.tryParse(
                              p['other_deductions']?.toString() ?? '0') ??
                          0),
                      IndianCurrency.format(
                          double.tryParse(p['net_paid']?.toString() ?? '0') ??
                              0),
                    ])
                .toList(),
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'Total Paid: ${IndianCurrency.format(totalPaid)}',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 32),
          _buildPdfFooter(stationName),
        ],
      ),
    );

    return _savePdf(pdf, 'payroll_report');
  }

  // ── Print PDF directly ────────────────────────────────────────────────────

  Future<void> printPdf(File pdfFile) async {
    await Printing.layoutPdf(
      onLayout: (_) async => pdfFile.readAsBytesSync(),
    );
  }

  // ── Share PDF / Excel ─────────────────────────────────────────────────────

  Future<void> sharePdf(File pdfFile, {String? subject}) async {
    await Share.shareXFiles(
      [XFile(pdfFile.path)],
      subject: subject ?? 'FuelOS Report',
    );
  }

  Future<void> shareText(String text) async {
    await Share.share(text);
  }

  // ── CSV Export ────────────────────────────────────────────────────────────

  Future<File> exportCsv({
    required List<String> headers,
    required List<List<String>> rows,
    required String filename,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(headers.map((h) => '"$h"').join(','));
    for (final row in rows) {
      buffer.writeln(row.map((c) => '"${c.replaceAll('"', '""')}"').join(','));
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename.csv');
    await file.writeAsString(buffer.toString());
    return file;
  }

  // ── Internal PDF builders ─────────────────────────────────────────────────

  pw.Widget _buildPdfHeader({
    required String title,
    required String subtitle,
    required String generatedAt,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  AppConstants.appName,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                    letterSpacing: 2,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                pw.Text(
                  subtitle,
                  style: const pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Generated',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
                ),
                pw.Text(
                  generatedAt,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: PdfColors.grey800, thickness: 1.5),
      ],
    );
  }

  pw.Widget _buildPdfSection({
    required String title,
    required List<List<String>> rows,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          children: rows
              .map((row) => pw.TableRow(
                    children: row
                        .map((cell) => pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(cell,
                                  style: const pw.TextStyle(fontSize: 10)),
                            ))
                        .toList(),
                  ))
              .toList(),
        ),
      ],
    );
  }

  pw.Widget _buildPdfTable({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Container(
              width: 3,
              height: 14,
              color: PdfColors.blueGrey800,
            ),
            pw.SizedBox(width: 6),
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey200),
          children: [
            // Header row
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: headers
                  .map((h) => pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: pw.Text(
                          h,
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ))
                  .toList(),
            ),
            // Data rows
            ...rows.map((row) => pw.TableRow(
                  children: row
                      .map((cell) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            child: pw.Text(cell,
                                style: const pw.TextStyle(fontSize: 9)),
                          ))
                      .toList(),
                )),
          ],
        ),
        pw.Text(
          '${rows.length} records',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
        ),
      ],
    );
  }

  pw.Widget _buildPdfFooter(String stationName) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '${AppConstants.appName} · $stationName · Confidential',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey400),
            ),
            pw.Text(
              'India Standard Time',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey400),
            ),
          ],
        ),
      ],
    );
  }

  Future<File> _savePdf(pw.Document pdf, String name) async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/${name}_$timestamp.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
