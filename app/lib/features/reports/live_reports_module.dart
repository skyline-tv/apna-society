import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
import '../../api/models/flat_label.dart';
import '../../api/models/report_models.dart';
import '../../api/models/society_models.dart';
import '../../api/repositories/live_repositories.dart';
import '../../app_core.dart';
import '../../ui/components.dart';
import '../../ui/load_failure.dart';

String reportErrorMessage(Object error) {
  if (error is ApiException) {
    switch (error.code) {
      case 'FORBIDDEN_ROLE':
        return 'You do not have access to admin reports.';
      case 'INVALID_EXPORT_TYPE':
        return 'Unknown export type.';
      default:
        return error.message;
    }
  }
  if (error is StateError) return error.message;
  return '$error';
}

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _isoDay(DateTime d) => '${_ymd(d)}T00:00:00.000Z';

String _periodLabel(String from, String to, {String? wingCode}) {
  final f = from.length >= 10 ? fmtYmd(from.substring(0, 10)) : from;
  final t = to.length >= 10 ? fmtYmd(to.substring(0, 10)) : to;
  return '$f – $t${wingCode != null ? ' · Wing $wingCode' : ''}';
}

String _pct(num v) => '${v.toStringAsFixed(1)}%';

String _monthLabel(int year, int? month) {
  if (month == null || month < 1 || month > 12) return '$year';
  return '${kMonths[month - 1]} $year';
}

String _exportLabel(String type) {
  switch (type) {
    case 'financial':
      return 'Financial summary';
    case 'collections':
      return 'Collections by wing';
    case 'outstanding':
      return 'Outstanding dues';
    case 'payments':
      return 'Payment ledger';
    case 'complaints':
      return 'Complaints';
    default:
      return humanizeStatus(type);
  }
}

class LiveAdminReportsPage extends StatefulWidget {
  const LiveAdminReportsPage({super.key});

  @override
  State<LiveAdminReportsPage> createState() => _LiveAdminReportsPageState();
}

class _LiveAdminReportsPageState extends State<LiveAdminReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  late Future<_ReportsBundle> _future = _load();

  DateTime? _from;
  DateTime? _to;
  String? _wingCode;
  int _outstandingPage = 1;
  List<WingSummary> _wings = const [];
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadWings();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  ReportQuery get _query => ReportQuery(
        from: _from == null ? null : _isoDay(_from!),
        to: _to == null ? null : _isoDay(_to!),
        wingCode: _wingCode,
        page: _outstandingPage,
        limit: 50,
      );

  Future<void> _loadWings() async {
    try {
      final session = authSession;
      if (session == null) return;
      final wings = await ensureLiveRepositories(session.api).society.wings();
      if (mounted) setState(() => _wings = wings);
    } catch (_) {}
  }

  Future<_ReportsBundle> _load({bool force = false}) async {
    final session = authSession;
    if (session == null) throw StateError('Not signed in.');
    final repos = ensureLiveRepositories(session.api);
    final q = _query;
    final results = await Future.wait([
      repos.society.dashboard(force: force),
      repos.reports.dashboard(query: q, force: force),
      repos.reports.financial(query: q, force: force),
      repos.reports.collections(query: q, force: force),
      repos.reports.outstanding(query: q, force: force),
    ]);
    return _ReportsBundle(
      society: results[0] as DashboardStats,
      dashboard: results[1] as ReportsDashboard,
      financial: results[2] as FinancialReport,
      collections: results[3] as CollectionReport,
      outstanding: results[4] as OutstandingReport,
    );
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _refresh() async {
    reload();
    await _future;
  }

  bool get _filtered => _from != null || _to != null || _wingCode != null;

  void _clearFilters() => setState(() {
        _from = null;
        _to = null;
        _wingCode = null;
        _outstandingPage = 1;
        _future = _load(force: true);
      });

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: _to ?? DateTime.now().add(const Duration(days: 1)),
      helpText: 'Report from',
    );
    if (picked != null) {
      setState(() {
        _from = picked;
        _outstandingPage = 1;
        _future = _load(force: true);
      });
    }
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? DateTime.now(),
      firstDate: _from ?? DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Report to',
    );
    if (picked != null) {
      setState(() {
        _to = picked;
        _outstandingPage = 1;
        _future = _load(force: true);
      });
    }
  }

  Future<void> _pickWing() async {
    final picked = await showAppSheet<String>(
      context,
      title: 'Filter by wing',
      builder: (ctx) => Column(children: [
        ListRow(
          dense: true,
          title: 'All wings',
          leading: const AppAvatar(
              icon: Icons.domain_outlined, square: true, size: 36),
          trailing: _wingCode == null
              ? const Icon(Icons.check_rounded, color: C.blue)
              : null,
          showChevron: false,
          onTap: () => Navigator.pop(ctx, ''),
        ),
        for (final w in _wings)
          ListRow(
            dense: true,
            title: w.name,
            subtitle: '${w.flatCount} flats',
            leading: AppAvatar(text: w.code, square: true, size: 36),
            trailing: _wingCode == w.code
                ? const Icon(Icons.check_rounded, color: C.blue)
                : null,
            showChevron: false,
            onTap: () => Navigator.pop(ctx, w.code),
          ),
      ]),
    );
    if (picked == null) return;
    setState(() {
      _wingCode = picked.isEmpty ? null : picked;
      _outstandingPage = 1;
      _future = _load(force: true);
    });
  }

  Future<void> _export(String type, {String? from, String? to}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final session = authSession;
      if (session == null) throw StateError('Not signed in.');
      final bytes = await ensureLiveRepositories(session.api).reports.exportCsv(
            type,
            query: _query,
          );
      if (bytes.isEmpty) {
        throw StateError('Export returned no data.');
      }
      final name = reportCsvFilename(type: type, from: from, to: to);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              mimeType: 'text/csv',
              name: name,
            ),
          ],
          subject: 'ApnaSociety $type report',
          text: 'ApnaSociety $type report ($name)',
        ),
      );
    } catch (e) {
      if (mounted) showErrorSnack(context, reportErrorMessage(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _exportButton(String type,
      {required String from, required String to}) {
    return SecondaryButton(
      label: 'Export ${_exportLabel(type).toLowerCase()} (CSV)',
      icon: Icons.ios_share_rounded,
      busy: _exporting,
      onPressed: () => _export(type, from: from, to: to),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: FilterBar(
            padding: EdgeInsets.zero,
            children: [
              AppFilterChip(
                label: _from == null ? 'From' : fmtDate(_from!),
                icon: Icons.calendar_today_outlined,
                selected: _from != null,
                onSelected: _pickFrom,
              ),
              AppFilterChip(
                label: _to == null ? 'To' : fmtDate(_to!),
                icon: Icons.event_outlined,
                selected: _to != null,
                onSelected: _pickTo,
              ),
              if (_wings.isNotEmpty)
                AppFilterChip(
                  label: _wingCode == null ? 'All wings' : 'Wing $_wingCode',
                  icon: Icons.domain_outlined,
                  selected: _wingCode != null,
                  onSelected: _pickWing,
                ),
              if (_filtered)
                AppFilterChip(
                  label: 'Clear',
                  icon: Icons.close_rounded,
                  selected: false,
                  onSelected: _clearFilters,
                ),
            ],
          ),
        ),
        Container(
          color: C.surface,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Financial'),
              Tab(text: 'Collections'),
              Tab(text: 'Outstanding'),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<_ReportsBundle>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const SkeletonList(items: 5, showHeader: true);
              }
              if (snap.hasError) {
                return LoadFailure(
                    error: snap.error!,
                    title: 'Could not load reports',
                    onRetry: reload);
              }
              final b = snap.data!;
              return TabBarView(
                controller: _tabs,
                children: [
                  _wrap(_dashboardTab(b)),
                  _wrap(_financialTab(b.financial)),
                  _wrap(_collectionsTab(b.collections)),
                  _wrap(_outstandingTab(b.outstanding)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _wrap(List<Widget> children) => RefreshIndicator(
        color: C.blue,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: Sp.pagePadding,
          children: children,
        ),
      );

  List<Widget> _dashboardTab(_ReportsBundle b) {
    final fin = b.dashboard.financial;
    final col = b.dashboard.collections;
    final soc = b.society.totals;
    final occupied = soc.ownerOccupiedFlats + soc.tenantOccupiedFlats;
    return [
      PageHeader(
        'Society overview',
        subtitle: _periodLabel(b.dashboard.from, b.dashboard.to,
            wingCode: b.dashboard.wingCode),
      ),
      HeroMoneyCard(
        label: 'Outstanding principal',
        amount:
            moneyPaise(b.dashboard.outstandingTotals.outstandingPrincipalPaise),
        subtitle:
            'Collected ${moneyPaise(fin.totalCollectedPaise)} of ${moneyPaise(fin.totalBilledPaise)} billed · ${_pct(col.collectionPercentage)}',
      ),
      const SizedBox(height: 12),
      MetricBand(items: [
        MetricItem('Flats', '${soc.flats}'),
        MetricItem('Occupied', '$occupied'),
        MetricItem('Vacant', '${soc.vacantFlats}',
            valueColor: soc.vacantFlats > 0 ? C.amber : C.navy),
        MetricItem('Collection rate', _pct(col.collectionPercentage),
            valueColor: C.green),
      ]),
      const SizedBox(height: 12),
      MetricBand(items: [
        MetricItem('Monthly maintenance', money(soc.monthlyMaintenanceTotal)),
        MetricItem(
            'Accrued interest', moneyPaise(fin.totalAccruedInterestPaise),
            valueColor: fin.totalAccruedInterestPaise > 0 ? C.amber : C.navy),
        MetricItem('Collected', moneyPaise(fin.totalCollectedPaise),
            valueColor: C.green),
      ]),
      const SizedBox(height: 14),
      DetailCard(title: 'Collections snapshot', children: [
        DetailRow('Bills generated', '${col.totalBillsGenerated}'),
        DetailRow('Paid', '${col.paidBills}'),
        DetailRow('Partially paid', '${col.partiallyPaidBills}'),
        DetailRow('Unpaid', '${col.unpaidBills}'),
        DetailRow('Overdue', '${col.overdueBills}'),
        DetailRow('Collection rate', _pct(col.collectionPercentage),
            emphasize: true),
      ]),
      if (b.dashboard.topFlats.isNotEmpty) ...[
        const SectionTitle('Top outstanding flats'),
        AppCard(
          margin: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < b.dashboard.topFlats.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 56, endIndent: 12),
              Builder(builder: (_) {
                final f = b.dashboard.topFlats[i];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(children: [
                    AppAvatar(text: f.wingCode, square: true, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(formatFlatLabel(f.wingCode, f.flatNumber),
                              style: T.bodyStrong),
                          const SizedBox(height: 2),
                          Text(f.ownerNameSnapshot, style: T.caption),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(moneyPaise(f.outstandingPrincipalPaise),
                            style: T.money.copyWith(fontSize: 13)),
                        if (f.accruedInterestPaise > 0)
                          Text(
                              '+${moneyPaise(f.accruedInterestPaise)} interest',
                              style: T.caption),
                      ],
                    ),
                  ]),
                );
              }),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 16),
      const SectionTitle('Export',
          subtitle: 'CSV for the selected period and wing'),
      for (final type in reportExportTypes)
        if (type != 'complaints')
          QuickActionTile(
            icon: Icons.ios_share_rounded,
            label: _exportLabel(type),
            subtitle: 'Share as CSV',
            enabled: !_exporting,
            onTap: () =>
                _export(type, from: b.dashboard.from, to: b.dashboard.to),
          ),
      if (_exporting)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: LinearProgressIndicator(minHeight: 3),
        ),
    ];
  }

  List<Widget> _financialTab(FinancialReport r) {
    return [
      Text(_periodLabel(r.from, r.to), style: T.caption),
      const SizedBox(height: 12),
      HeroMoneyCard(
        label: 'Collected',
        amount: moneyPaise(r.totalCollectedPaise),
        subtitle:
            'of ${moneyPaise(r.totalBilledPaise)} billed · ${_pct(r.collectionPercentage)} across ${r.billCount} bills',
      ),
      const SizedBox(height: 14),
      DetailCard(title: 'Totals', children: [
        DetailRow('Billed', moneyPaise(r.totalBilledPaise)),
        DetailRow('Collected', moneyPaise(r.totalCollectedPaise)),
        DetailRow('Outstanding principal',
            moneyPaise(r.totalOutstandingPrincipalPaise),
            emphasize: true),
        DetailRow('Accrued interest', moneyPaise(r.totalAccruedInterestPaise)),
        DetailRow('Refunds', moneyPaise(r.totalRefundsPaise)),
      ]),
      DetailCard(title: 'Channels', children: [
        DetailRow(
            'Offline collections', moneyPaise(r.totalOfflineCollectionsPaise)),
        DetailRow(
            'Online collections', moneyPaise(r.totalOnlineCollectionsPaise)),
      ]),
      DetailCard(title: 'Payments', children: [
        DetailRow('Successful', '${r.paymentSuccessCount}'),
        DetailRow('Failed', '${r.paymentFailureCount}'),
        DetailRow('Refunded', '${r.paymentRefundedCount}'),
        DetailRow('Pending', '${r.paymentPendingCount}'),
      ]),
      if (r.note.trim().isNotEmpty) InfoNote(r.note),
      if (r.monthly.isNotEmpty) ...[
        const SectionTitle('Month by month'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < r.monthly.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        _monthLabel(r.monthly[i].year, r.monthly[i].month),
                        style: T.bodyStrong),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(moneyPaise(r.monthly[i].collectedPaise),
                        style: T.money),
                    Text(
                      'of ${moneyPaise(r.monthly[i].billedPaise)} · due ${moneyPaise(r.monthly[i].outstandingPrincipalPaise)}',
                      style: T.caption,
                    ),
                  ]),
                ]),
              ),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 16),
      _exportButton('financial', from: r.from, to: r.to),
      const SizedBox(height: 8),
      _exportButton('payments', from: r.from, to: r.to),
    ];
  }

  List<Widget> _collectionsTab(CollectionReport r) {
    return [
      Text(_periodLabel(r.from, r.to), style: T.caption),
      const SizedBox(height: 12),
      HeroMoneyCard(
        label: 'Collected',
        amount: moneyPaise(r.totalAmountCollectedPaise),
        subtitle:
            '${_pct(r.collectionPercentage)} of ${moneyPaise(r.totalBilledPaise)} billed · ${r.totalBillsGenerated} bills',
      ),
      const SizedBox(height: 14),
      MiniStatStrip(children: [
        MiniStat('Paid', '${r.paidBills}', tone: BadgeTone.success),
        MiniStat('Partial', '${r.partiallyPaidBills}', tone: BadgeTone.warning),
        MiniStat('Unpaid', '${r.unpaidBills}', tone: BadgeTone.neutral),
        MiniStat('Overdue', '${r.overdueBills}',
            tone: r.overdueBills > 0 ? BadgeTone.danger : BadgeTone.neutral),
      ]),
      const SizedBox(height: 10),
      DetailCard(title: 'Totals', children: [
        DetailRow('Billed', moneyPaise(r.totalBilledPaise)),
        DetailRow('Collected', moneyPaise(r.totalAmountCollectedPaise)),
        DetailRow('Outstanding', moneyPaise(r.totalAmountOutstandingPaise),
            emphasize: true),
        DetailRow('Collection rate', _pct(r.collectionPercentage)),
      ]),
      if (r.collectionPercentageFormula.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(r.collectionPercentageFormula, style: T.caption),
        ),
      const SectionTitle('By wing'),
      if (r.wingWise.isEmpty)
        const EmptyState('No wing collection data', compact: true)
      else
        for (final w in r.wingWise)
          ListRow(
            leading: AppAvatar(text: w.wingCode, square: true),
            title: 'Wing ${w.wingCode}',
            subtitle:
                'Billed ${moneyPaise(w.billedPaise)} · Outstanding ${moneyPaise(w.outstandingPrincipalPaise)}',
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(moneyPaise(w.collectedPaise), style: T.money),
                Text(_pct(w.collectionPercentage), style: T.caption),
              ],
            ),
            showChevron: false,
          ),
      const SizedBox(height: 16),
      _exportButton('collections', from: r.from, to: r.to),
    ];
  }

  List<Widget> _outstandingTab(OutstandingReport r) {
    return [
      Text(_periodLabel(r.from, r.to), style: T.caption),
      const SizedBox(height: 12),
      HeroMoneyCard(
        label: 'Outstanding principal',
        amount: moneyPaise(r.outstandingPrincipalPaise),
        subtitle:
            '+ ${moneyPaise(r.accruedInterestPaise)} accrued interest · ${r.flatCount} flat${r.flatCount == 1 ? '' : 's'}',
      ),
      const SizedBox(height: 14),
      if (r.items.isEmpty)
        const EmptyState('No outstanding dues in this period',
            icon: Icons.task_alt_rounded)
      else ...[
        ResultCount(r.pagination.total, 'flat'),
        for (final f in r.items)
          ListRow(
            leading: AppAvatar(text: f.wingCode, square: true),
            title: formatFlatLabel(f.wingCode, f.flatNumber),
            subtitle:
                '${f.ownerNameSnapshot}\nBilled ${moneyPaise(f.billedPaise)} · Collected ${moneyPaise(f.collectedPaise)}',
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(moneyPaise(f.outstandingPrincipalPaise), style: T.money),
                if (f.accruedInterestPaise > 0)
                  Text('+${moneyPaise(f.accruedInterestPaise)} interest',
                      style: T.caption),
              ],
            ),
            showChevron: false,
          ),
        PaginationBar(
          page: r.pagination.page,
          totalPages: r.pagination.totalPages,
          onPrevious: () => setState(() {
            _outstandingPage = r.pagination.page - 1;
            _future = _load(force: true);
          }),
          onNext: () => setState(() {
            _outstandingPage = r.pagination.page + 1;
            _future = _load(force: true);
          }),
        ),
      ],
      const SizedBox(height: 12),
      _exportButton('outstanding', from: r.from, to: r.to),
    ];
  }
}

class _ReportsBundle {
  const _ReportsBundle({
    required this.society,
    required this.dashboard,
    required this.financial,
    required this.collections,
    required this.outstanding,
  });

  final DashboardStats society;
  final ReportsDashboard dashboard;
  final FinancialReport financial;
  final CollectionReport collections;
  final OutstandingReport outstanding;
}
