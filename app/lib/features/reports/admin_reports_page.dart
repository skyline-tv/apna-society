import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_core.dart';
import '../../services/late_interest.dart';
import '../../services/report_pdf.dart';
import '../../ui/components.dart';

/// Admin-only financial reports for Monarch Solitaire A to E.
class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Material(
            color: C.surface,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              labelColor: C.blue,
              unselectedLabelColor: C.muted,
              indicatorColor: C.blue,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Paid'),
                Tab(text: 'Unpaid'),
                Tab(text: 'Flat history'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                _ReportsOverviewTab(),
                _PaidBillsReportTab(),
                _UnpaidBillsReportTab(),
                _FlatHistoryReportTab(),
              ],
            ),
          ),
        ],
      );
}

// ── Shared helpers ───────────────────────────────────────────────────────────

Map<String, dynamic> _rowMap(dynamic row) =>
    Map<String, dynamic>.from(row.data as Map);

Future<List<Map<String, dynamic>>> _enrichWithInterest(
    List<dynamic> rows) async {
  final out = <Map<String, dynamic>>[];
  for (final r in rows) {
    final m = _rowMap(r);
    final s =
        await db.billInterestSummary(r.read<int>('id'), persistLedger: false);
    m['interest_outstanding'] = s.interestOutstanding;
    m['total_outstanding'] = s.totalOutstanding;
    m['overdue_months'] = s.overdueMonths;
    out.add(m);
  }
  return out;
}

Future<Map<int, BillInterestSummary>> _interestMapForRows(
    List<dynamic> rows) async {
  final map = <int, BillInterestSummary>{};
  for (final r in rows) {
    final id = r.read<int>('id') as int;
    map[id] = await db.billInterestSummary(id, persistLedger: false);
  }
  return map;
}

String _wingLabel(String? building) {
  if (building == null || building.isEmpty) return '—';
  return building.replaceFirst('Monarch Solitaire ', '');
}

String _periodLabel(dynamic row) {
  final start = row.read<String>('period_start');
  final months = row.data['months_covered'] as int? ?? 1;
  final end = row.data['period_end'] as String?;
  return ReportPdf.periodLabel(start, months, periodEnd: end);
}

int _daysOverdue(dynamic row) {
  return ReportPdf.daysOverdue(
      row.read<String>('due_date'), row.read<String>('status'));
}

String _isoDate(DateTime? d) =>
    d == null ? '' : d.toIso8601String().substring(0, 10);

String _filtersLabel({
  required String wing,
  required String flatQuery,
  int? year,
  int? month,
  DateTime? paidFrom,
  DateTime? paidTo,
  DateTime? dueFrom,
  DateTime? dueTo,
  String? statusLabel,
}) {
  final parts = <String>[];
  if (year != null && month != null) {
    parts.add('${kMonths[month - 1]} $year');
  } else if (year != null) {
    parts.add('Year $year');
  } else {
    parts.add('All periods');
  }
  parts.add(wing == 'All' ? 'All wings' : wing);
  if (flatQuery.trim().isNotEmpty) parts.add('Flat ~ ${flatQuery.trim()}');
  if (paidFrom != null || paidTo != null) {
    parts.add(
        'Paid ${_isoDate(paidFrom).isEmpty ? '…' : _isoDate(paidFrom)} → ${_isoDate(paidTo).isEmpty ? '…' : _isoDate(paidTo)}');
  }
  if (dueFrom != null || dueTo != null) {
    parts.add(
        'Due ${_isoDate(dueFrom).isEmpty ? '…' : _isoDate(dueFrom)} → ${_isoDate(dueTo).isEmpty ? '…' : _isoDate(dueTo)}');
  }
  if (statusLabel != null && statusLabel.isNotEmpty) parts.add(statusLabel);
  return parts.join(' · ');
}

Future<void> _pickDate(BuildContext context, ValueChanged<DateTime?> onPicked,
    {DateTime? initial}) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
  onPicked(picked);
}

Future<void> _exportActions(
  BuildContext context, {
  required String title,
  required Future<Uint8List> Function() buildPdf,
  required String fileKind,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        const Center(child: CircularProgressIndicator(color: C.blue)),
  );
  try {
    final bytes = await buildPdf();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: C.navy)),
              const SizedBox(height: 4),
              Text(
                  'PDF ready (${bytes.length ~/ 1024} KB). Preview, save, or share via WhatsApp and other apps.',
                  style: const TextStyle(
                      color: C.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetCtx);
                  await ReportPdf.previewBytes(
                      bytes, ReportPdf.fileName(fileKind));
                },
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview PDF'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetCtx);
                  await ReportPdf.shareBytes(
                      bytes, ReportPdf.fileName(fileKind));
                  messenger.showSnackBar(const SnackBar(
                      content: Text(
                          'Use Save / WhatsApp / other apps from the share sheet.'),
                      backgroundColor: C.green));
                },
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Download / Share PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
          SnackBar(content: Text('PDF failed: $e'), backgroundColor: C.error));
    }
  }
}

Widget _miniStat(String label, String value, {Color? accent}) => Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: accent ?? C.navy)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: C.muted, fontWeight: FontWeight.w600)),
        ]),
      ),
    );

Widget _filterField({required String label, required Widget child}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: C.muted)),
        const SizedBox(height: 4),
        child,
      ]),
    );

// ── Overview ─────────────────────────────────────────────────────────────────

class _ReportsOverviewTab extends StatefulWidget {
  const _ReportsOverviewTab();
  @override
  State<_ReportsOverviewTab> createState() => _ReportsOverviewTabState();
}

class _ReportsOverviewTabState extends State<_ReportsOverviewTab> {
  late Future<Map<String, int>> _future;

  @override
  void initState() {
    super.initState();
    _future = db.summary();
  }

  void reload() {
    setState(() {
      _future = db.summary();
    });
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: C.blue,
        onRefresh: () async => reload(),
        child: FutureBuilder<Map<String, int>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const LoadingView(label: 'Loading report summary…');
            }
            if (snap.hasError) {
              return ListView(children: [
                EmptyState('Could not load reports.\n${snap.error}',
                    icon: Icons.error_outline)
              ]);
            }
            final s = snap.data ?? {};
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                const SectionTitle('Payment reports'),
                const SizedBox(height: 6),
                const Text(
                    'Live totals from local bills and payments. Cancelled bills are excluded from collection.',
                    style: TextStyle(
                        color: C.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          title: 'Total flats',
                          value: '${s['flats'] ?? 0}',
                          icon: Icons.apartment_outlined)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          title: 'Bills generated',
                          value: '${s['bills'] ?? 0}',
                          icon: Icons.receipt_long_outlined)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          title: 'Paid bills',
                          value: '${s['paid'] ?? 0}',
                          icon: Icons.check_circle_outline,
                          accent: C.green)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          title: 'Unpaid bills',
                          value: '${s['unpaidBills'] ?? 0}',
                          icon: Icons.pending_actions_outlined,
                          accent: C.amber)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          title: 'Overdue bills',
                          value: '${s['overdue'] ?? 0}',
                          icon: Icons.warning_amber_rounded,
                          accent: C.error)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          title: 'Amount billed',
                          value: money(s['billedAmount'] ?? 0),
                          icon: Icons.request_quote_outlined)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          title: 'Amount collected',
                          value: money(s['collection'] ?? 0),
                          icon: Icons.payments_outlined,
                          accent: C.green)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          title: 'Outstanding',
                          value: money(s['outstandingAmount'] ?? 0),
                          icon: Icons.account_balance_wallet_outlined,
                          accent: C.error)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: StatCard(
                          title: 'Principal due',
                          value: money(s['outstandingPrincipal'] ?? 0),
                          icon: Icons.request_quote_outlined,
                          accent: C.amber)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: StatCard(
                          title: 'Late interest due',
                          value: money(s['outstandingInterest'] ?? 0),
                          icon: Icons.percent,
                          accent: C.error)),
                ]),
                const SizedBox(height: 18),
                const SectionTitle('Export reports'),
                const SizedBox(height: 10),
                QuickActionTile(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Complete Maintenance Collection Report',
                  onTap: () => _exportActions(
                    context,
                    title: 'Collection Report',
                    fileKind: 'Collection',
                    buildPdf: () async {
                      final rows = await db.reportBills(status: 'all');
                      final totals = await db.reportTotals(rows);
                      return ReportPdf.collectionReportPdf(
                        allRows: rows.map(_rowMap).toList(),
                        filtersLabel: 'All periods · All wings',
                        totals: totals,
                      );
                    },
                  ),
                ),
                const InfoNote(
                    'Open Paid, Unpaid, or Flat history tabs for filtered reports with PDF preview and native share (including WhatsApp).'),
              ],
            );
          },
        ),
      );
}

// ── Paid ─────────────────────────────────────────────────────────────────────

class _PaidBillsReportTab extends StatefulWidget {
  const _PaidBillsReportTab();
  @override
  State<_PaidBillsReportTab> createState() => _PaidBillsReportTabState();
}

class _PaidBillsReportTabState extends State<_PaidBillsReportTab> {
  String wing = 'All';
  final flatCtrl = TextEditingController();
  int? year;
  int? month;
  DateTime? paidFrom;
  DateTime? paidTo;
  late Future<_ReportBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    flatCtrl.dispose();
    super.dispose();
  }

  Future<_ReportBundle> _load() async {
    final rows = await db.reportBills(
      status: 'paid',
      building: wing,
      flatNumberContains: flatCtrl.text,
      periodYear: year,
      periodMonth: month,
      paidFrom: _isoDate(paidFrom),
      paidTo: _isoDate(paidTo),
    );
    final totals = await db.reportTotals(rows);
    return _ReportBundle(rows, totals);
  }

  void reload() {
    setState(() {
      _future = _load();
    });
  }

  String get filtersLabel => _filtersLabel(
        wing: wing,
        flatQuery: flatCtrl.text,
        year: year,
        month: month,
        paidFrom: paidFrom,
        paidTo: paidTo,
        statusLabel: 'Paid only',
      );

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: FutureBuilder<_ReportBundle>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const LoadingView(label: 'Loading paid bills…');
                }
                if (snap.hasError) {
                  return EmptyState('Error: ${snap.error}',
                      icon: Icons.error_outline);
                }
                final bundle = snap.data ?? _ReportBundle(const [], {});
                final rows = bundle.rows;
                final t = bundle.totals;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  children: [
                    _PaidFilters(
                      wing: wing,
                      year: year,
                      month: month,
                      paidFrom: paidFrom,
                      paidTo: paidTo,
                      flatCtrl: flatCtrl,
                      onWing: (v) => setState(() => wing = v),
                      onYear: (v) => setState(() => year = v),
                      onMonth: (v) => setState(() => month = v),
                      onPaidFrom: (v) => setState(() => paidFrom = v),
                      onPaidTo: (v) => setState(() => paidTo = v),
                      onApply: reload,
                      onClear: () {
                        wing = 'All';
                        year = null;
                        month = null;
                        paidFrom = null;
                        paidTo = null;
                        flatCtrl.clear();
                        reload();
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      _miniStat('Paid bills', '${t['paidCount'] ?? 0}',
                          accent: C.green),
                      const SizedBox(width: 8),
                      _miniStat('Collection', money(t['collected'] ?? 0),
                          accent: C.green),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _exportActions(
                            context,
                            title: 'Paid Bills Report',
                            fileKind: 'Paid',
                            buildPdf: () async => ReportPdf.paidReportPdf(
                              records: rows.map(_rowMap).toList(),
                              filtersLabel: filtersLabel,
                              totals: t,
                            ),
                          ),
                          icon: const Icon(Icons.picture_as_pdf_outlined,
                              size: 18),
                          label: const Text('Export PDF'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (rows.isEmpty)
                      const EmptyState(
                          'No paid bills for these filters.\nYou can still export an empty PDF.')
                    else
                      ...rows.map((r) => AppCard(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(
                                          '${r.read<String>('flat_number')} · ${_wingLabel(r.read<String>('building'))}',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: C.navy)),
                                    ),
                                    const StatusBadge('paid'),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text(
                                      '${r.read<String>('owner_name')} · ${r.data['flat_type'] ?? '—'}',
                                      style: const TextStyle(
                                          color: C.muted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  billDetailLine(
                                      'Maintenance Period', _periodLabel(r)),
                                  ...billAmountBreakdownLines(r),
                                  billDetailLine(
                                      'Payment date',
                                      shortDate(
                                          r.data['paid_at'] as String? ?? '')),
                                  billDetailLine('Method', () {
                                    final m =
                                        r.data['payment_method'] as String? ??
                                            '—';
                                    if (m == 'Cheque') {
                                      final cs =
                                          r.data['cheque_status'] as String? ??
                                              'Pending';
                                      return cs == 'Pending'
                                          ? 'Cheque Recorded'
                                          : 'Cheque · $cs';
                                    }
                                    return m;
                                  }()),
                                  billDetailLine('Receipt',
                                      '${r.data['receipt_number'] ?? '—'}'),
                                  if ((r.data['cheque_number'] as String?)
                                          ?.isNotEmpty ==
                                      true)
                                    billDetailLine('Cheque / Bank',
                                        '${r.data['cheque_number']} · ${r.data['bank_name'] ?? '—'}'),
                                ]),
                          )),
                  ],
                );
              },
            ),
          ),
        ],
      );
}

class _PaidFilters extends StatelessWidget {
  const _PaidFilters({
    required this.wing,
    required this.year,
    required this.month,
    required this.paidFrom,
    required this.paidTo,
    required this.flatCtrl,
    required this.onWing,
    required this.onYear,
    required this.onMonth,
    required this.onPaidFrom,
    required this.onPaidTo,
    required this.onApply,
    required this.onClear,
  });

  final String wing;
  final int? year;
  final int? month;
  final DateTime? paidFrom;
  final DateTime? paidTo;
  final TextEditingController flatCtrl;
  final ValueChanged<String> onWing;
  final ValueChanged<int?> onYear;
  final ValueChanged<int?> onMonth;
  final ValueChanged<DateTime?> onPaidFrom;
  final ValueChanged<DateTime?> onPaidTo;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Filters',
              style: TextStyle(fontWeight: FontWeight.w900, color: C.navy)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _filterField(
                label: 'Month',
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('paid-month-$month'),
                  initialValue: month,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    for (var i = 1; i <= 12; i++)
                      DropdownMenuItem(value: i, child: Text(kMonths[i - 1])),
                  ],
                  onChanged: onMonth,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _filterField(
                label: 'Year',
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('paid-year-$year'),
                  initialValue: year,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    for (var y = DateTime.now().year;
                        y >= DateTime.now().year - 5;
                        y--)
                      DropdownMenuItem(value: y, child: Text('$y')),
                  ],
                  onChanged: onYear,
                ),
              ),
            ),
          ]),
          _filterField(
            label: 'Wing',
            child: DropdownButtonFormField<String>(
              key: ValueKey('paid-wing-$wing'),
              initialValue: wing,
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                const DropdownMenuItem(value: 'All', child: Text('All wings')),
                ...kAllBuildings.map((b) =>
                    DropdownMenuItem(value: b, child: Text(_wingLabel(b)))),
              ],
              onChanged: (v) => onWing(v ?? 'All'),
            ),
          ),
          _filterField(
            label: 'Flat number',
            child: TextField(
              controller: flatCtrl,
              decoration:
                  const InputDecoration(isDense: true, hintText: 'e.g. 101'),
              onSubmitted: (_) => onApply(),
            ),
          ),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () =>
                    _pickDate(context, onPaidFrom, initial: paidFrom),
                child: Text(
                    paidFrom == null
                        ? 'Paid from'
                        : shortDate(_isoDate(paidFrom)),
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDate(context, onPaidTo, initial: paidTo),
                child: Text(
                    paidTo == null ? 'Paid to' : shortDate(_isoDate(paidTo)),
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: FilledButton(
                    onPressed: onApply, child: const Text('Apply'))),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: onClear, child: const Text('Clear')),
          ]),
        ]),
      );
}

// ── Unpaid / Overdue ─────────────────────────────────────────────────────────

class _UnpaidBillsReportTab extends StatefulWidget {
  const _UnpaidBillsReportTab();
  @override
  State<_UnpaidBillsReportTab> createState() => _UnpaidBillsReportTabState();
}

class _UnpaidBillsReportTabState extends State<_UnpaidBillsReportTab> {
  String wing = 'All';
  String statusFilter = 'unpaid'; // unpaid | pending | overdue
  final flatCtrl = TextEditingController();
  int? year;
  int? month;
  DateTime? dueFrom;
  DateTime? dueTo;
  late Future<_ReportBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    flatCtrl.dispose();
    super.dispose();
  }

  Future<_ReportBundle> _load() async {
    final rows = await db.reportBills(
      status: statusFilter,
      building: wing,
      flatNumberContains: flatCtrl.text,
      periodYear: year,
      periodMonth: month,
      dueFrom: _isoDate(dueFrom),
      dueTo: _isoDate(dueTo),
    );
    final totals = await db.reportTotals(rows);
    final interest = await _interestMapForRows(rows);
    return _ReportBundle(rows, totals, interestById: interest);
  }

  void reload() {
    setState(() {
      _future = _load();
    });
  }

  String get filtersLabel => _filtersLabel(
        wing: wing,
        flatQuery: flatCtrl.text,
        year: year,
        month: month,
        dueFrom: dueFrom,
        dueTo: dueTo,
        statusLabel: statusFilter == 'overdue'
            ? 'Overdue only'
            : statusFilter == 'pending'
                ? 'Unpaid (not overdue)'
                : 'Unpaid + Overdue',
      );

  @override
  Widget build(BuildContext context) => FutureBuilder<_ReportBundle>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const LoadingView(label: 'Loading unpaid bills…');
          }
          if (snap.hasError) {
            return EmptyState('Error: ${snap.error}',
                icon: Icons.error_outline);
          }
          final bundle = snap.data ?? _ReportBundle(const [], {});
          final rows = bundle.rows;
          final t = bundle.totals;
          final interestById = bundle.interestById;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Filters',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, color: C.navy)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final e in const [
                            ('unpaid', 'All unpaid'),
                            ('pending', 'Unpaid'),
                            ('overdue', 'Overdue'),
                          ])
                            ChoiceChip(
                              label: Text(e.$2),
                              selected: statusFilter == e.$1,
                              onSelected: (_) {
                                statusFilter = e.$1;
                                reload();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: _filterField(
                            label: 'Month',
                            child: DropdownButtonFormField<int?>(
                              key: ValueKey('unpaid-month-$month'),
                              initialValue: month,
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true),
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('All')),
                                for (var i = 1; i <= 12; i++)
                                  DropdownMenuItem(
                                      value: i, child: Text(kMonths[i - 1])),
                              ],
                              onChanged: (v) => setState(() => month = v),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _filterField(
                            label: 'Year',
                            child: DropdownButtonFormField<int?>(
                              key: ValueKey('unpaid-year-$year'),
                              initialValue: year,
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true),
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('All')),
                                for (var y = DateTime.now().year;
                                    y >= DateTime.now().year - 5;
                                    y--)
                                  DropdownMenuItem(value: y, child: Text('$y')),
                              ],
                              onChanged: (v) => setState(() => year = v),
                            ),
                          ),
                        ),
                      ]),
                      _filterField(
                        label: 'Wing',
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('unpaid-wing-$wing'),
                          initialValue: wing,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true),
                          items: [
                            const DropdownMenuItem(
                                value: 'All', child: Text('All wings')),
                            ...kAllBuildings.map((b) => DropdownMenuItem(
                                value: b, child: Text(_wingLabel(b)))),
                          ],
                          onChanged: (v) => setState(() => wing = v ?? 'All'),
                        ),
                      ),
                      _filterField(
                        label: 'Flat number',
                        child: TextField(
                          controller: flatCtrl,
                          decoration: const InputDecoration(
                              isDense: true, hintText: 'e.g. 204'),
                          onSubmitted: (_) => reload(),
                        ),
                      ),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(
                                context, (d) => setState(() => dueFrom = d),
                                initial: dueFrom),
                            child: Text(
                                dueFrom == null
                                    ? 'Due from'
                                    : shortDate(_isoDate(dueFrom)),
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(
                                context, (d) => setState(() => dueTo = d),
                                initial: dueTo),
                            child: Text(
                                dueTo == null
                                    ? 'Due to'
                                    : shortDate(_isoDate(dueTo)),
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: FilledButton(
                                onPressed: reload, child: const Text('Apply'))),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            wing = 'All';
                            statusFilter = 'unpaid';
                            year = null;
                            month = null;
                            dueFrom = null;
                            dueTo = null;
                            flatCtrl.clear();
                            reload();
                          },
                          child: const Text('Clear'),
                        ),
                      ]),
                    ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                _miniStat('Unpaid bills', '${t['unpaidCount'] ?? 0}',
                    accent: C.amber),
                const SizedBox(width: 8),
                _miniStat('Principal', money(t['outstandingPrincipal'] ?? 0),
                    accent: C.amber),
              ]),
              Row(children: [
                _miniStat('Late interest', money(t['outstandingInterest'] ?? 0),
                    accent: C.error),
                const SizedBox(width: 8),
                _miniStat('Total due', money(t['outstanding'] ?? 0),
                    accent: C.error),
              ]),
              Row(children: [
                _miniStat('Overdue bills', '${t['overdueCount'] ?? 0}',
                    accent: C.error),
                const SizedBox(width: 8),
                _miniStat('Overdue total', money(t['overdueAmount'] ?? 0),
                    accent: C.error),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _exportActions(
                      context,
                      title: statusFilter == 'overdue'
                          ? 'Overdue Bills Report'
                          : 'Unpaid Bills Report',
                      fileKind:
                          statusFilter == 'overdue' ? 'Overdue' : 'Unpaid',
                      buildPdf: () async => ReportPdf.unpaidReportPdf(
                        records: await _enrichWithInterest(rows),
                        filtersLabel: filtersLabel,
                        totals: t,
                        title: statusFilter == 'overdue'
                            ? 'Overdue Bills Report'
                            : 'Unpaid Bills Report',
                      ),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: Text(statusFilter == 'overdue'
                        ? 'Export Overdue PDF'
                        : 'Export Unpaid PDF'),
                  ),
                ),
              ]),
              if (statusFilter == 'unpaid') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final overdueRows = await db.reportBills(
                      status: 'overdue',
                      building: wing,
                      flatNumberContains: flatCtrl.text,
                      periodYear: year,
                      periodMonth: month,
                      dueFrom: _isoDate(dueFrom),
                      dueTo: _isoDate(dueTo),
                    );
                    final ot = await db.reportTotals(overdueRows);
                    if (!context.mounted) return;
                    await _exportActions(
                      context,
                      title: 'Overdue Bills Report',
                      fileKind: 'Overdue',
                      buildPdf: () async => ReportPdf.unpaidReportPdf(
                        records: await _enrichWithInterest(overdueRows),
                        filtersLabel: _filtersLabel(
                          wing: wing,
                          flatQuery: flatCtrl.text,
                          year: year,
                          month: month,
                          dueFrom: dueFrom,
                          dueTo: dueTo,
                          statusLabel: 'Overdue only',
                        ),
                        totals: ot,
                        title: 'Overdue Bills Report',
                      ),
                    );
                  },
                  icon: const Icon(Icons.warning_amber_rounded, size: 18),
                  label: const Text('Export Overdue-only PDF'),
                ),
              ],
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const EmptyState(
                    'No unpaid bills for these filters.\nYou can still export an empty PDF.')
              else
                ...rows.map((r) {
                  final status = r.read<String>('status');
                  final days = _daysOverdue(r);
                  final s = interestById[r.read<int>('id')];
                  return AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(
                                  '${r.read<String>('flat_number')} · ${_wingLabel(r.read<String>('building'))}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: C.navy)),
                            ),
                            StatusBadge(status),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                              '${r.read<String>('owner_name')} · ${r.data['mobile'] ?? '—'}',
                              style: const TextStyle(
                                  color: C.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          billDetailLine('Maintenance Period', _periodLabel(r)),
                          ...billAmountBreakdownLines(r),
                          if (s != null) ...[
                            ...billInterestBreakdownLines(s),
                            if (days > 0)
                              billDetailLine('Days past due', '$days'),
                          ],
                        ]),
                  );
                }),
            ],
          );
        },
      );
}

// ── Flat history ─────────────────────────────────────────────────────────────

class _FlatHistoryReportTab extends StatefulWidget {
  const _FlatHistoryReportTab();
  @override
  State<_FlatHistoryReportTab> createState() => _FlatHistoryReportTabState();
}

class _FlatHistoryReportTabState extends State<_FlatHistoryReportTab> {
  int? flatId;
  List<dynamic> allFlats = [];
  late Future<_ReportBundle?> _future;

  @override
  void initState() {
    super.initState();
    _future = Future.value(null);
    _loadFlats();
  }

  Future<void> _loadFlats() async {
    final flats = await db.flats(includeInactive: false);
    if (!mounted) return;
    setState(() => allFlats = flats);
  }

  Future<_ReportBundle?> _load() async {
    if (flatId == null) return null;
    final rows = await db.reportBills(status: 'all', flatId: flatId);
    final totals = await db.reportTotals(rows);
    return _ReportBundle(rows, totals);
  }

  void reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_ReportBundle?>(
        future: _future,
        builder: (context, snap) {
          final bundle = snap.data;
          dynamic selected;
          for (final f in allFlats) {
            if (f.read<int>('id') == flatId) {
              selected = f;
              break;
            }
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Select flat',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, color: C.navy)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        key: ValueKey('flat-$flatId'),
                        initialValue: flatId,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(hintText: 'Choose flat'),
                        items: allFlats
                            .map((f) => DropdownMenuItem(
                                  value: f.read<int>('id') as int,
                                  child: Text(
                                    '${_wingLabel(f.read<String>('building'))}-${f.read<String>('flat_number')} · ${f.read<String>('owner_name')}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) {
                          flatId = v;
                          reload();
                        },
                      ),
                    ]),
              ),
              if (flatId == null)
                const EmptyState(
                    'Select a flat to view complete billing history.')
              else if (snap.connectionState == ConnectionState.waiting &&
                  bundle == null)
                const Padding(
                    padding: EdgeInsets.all(40),
                    child: LoadingView(label: 'Loading flat statement…'))
              else if (snap.hasError)
                EmptyState('Error: ${snap.error}', icon: Icons.error_outline)
              else if (bundle != null) ...[
                const SizedBox(height: 4),
                Row(children: [
                  _miniStat('Bills', '${bundle.totals['rowCount'] ?? 0}'),
                  const SizedBox(width: 8),
                  _miniStat(
                      'Outstanding', money(bundle.totals['outstanding'] ?? 0),
                      accent: C.error),
                ]),
                Row(children: [
                  _miniStat('Collected', money(bundle.totals['collected'] ?? 0),
                      accent: C.green),
                  const SizedBox(width: 8),
                  _miniStat('Billed', money(bundle.totals['billed'] ?? 0)),
                ]),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: selected == null
                      ? null
                      : () => _exportActions(
                            context,
                            title: 'Individual Flat Statement',
                            fileKind:
                                'Flat_${selected.read<String>('flat_number')}',
                            buildPdf: () async => ReportPdf.flatStatementPdf(
                              building: selected.read<String>('building'),
                              flatNumber: selected.read<String>('flat_number'),
                              ownerName: selected.read<String>('owner_name'),
                              flatType: '${selected.data['flat_type'] ?? '—'}',
                              records: bundle.rows.map(_rowMap).toList(),
                              totals: bundle.totals,
                            ),
                          ),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Export Flat Statement PDF'),
                ),
                const SizedBox(height: 12),
                if (bundle.rows.isEmpty)
                  const EmptyState('No bills generated for this flat yet.')
                else
                  ...bundle.rows.map((r) => AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Text(_periodLabel(r),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: C.navy)),
                                ),
                                StatusBadge(r.read<String>('status')),
                              ]),
                              const SizedBox(height: 8),
                              ...billAmountBreakdownLines(r),
                              billDetailLine(
                                  'Due', shortDate(r.read<String>('due_date'))),
                              billDetailLine(
                                  'Paid on',
                                  (r.data['paid_at'] as String?)?.isNotEmpty ==
                                          true
                                      ? shortDate(r.data['paid_at'] as String)
                                      : '—'),
                              billDetailLine('Receipt',
                                  '${r.data['receipt_number'] ?? '—'}'),
                            ]),
                      )),
              ],
            ],
          );
        },
      );
}

class _ReportBundle {
  _ReportBundle(this.rows, this.totals, {this.interestById = const {}});
  final List<dynamic> rows;
  final Map<String, int> totals;
  final Map<int, BillInterestSummary> interestById;
}
