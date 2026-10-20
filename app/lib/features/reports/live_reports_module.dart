import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/auth/auth_session.dart';
import '../../api/http/api_exception.dart';
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

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _isoDay(DateTime d) => '${_ymd(d)}T00:00:00.000Z';

void _toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? C.error : null,
    ),
  );
}

class LiveAdminReportsPage extends StatefulWidget {
  const LiveAdminReportsPage({super.key});

  @override
  State<LiveAdminReportsPage> createState() => _LiveAdminReportsPageState();
}

class _LiveAdminReportsPageState extends State<LiveAdminReportsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
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
      repos.reports.complaints(query: q, force: force),
    ]);
    return _ReportsBundle(
      society: results[0] as DashboardStats,
      dashboard: results[1] as ReportsDashboard,
      financial: results[2] as FinancialReport,
      collections: results[3] as CollectionReport,
      outstanding: results[4] as OutstandingReport,
      complaints: results[5] as ComplaintReport,
    );
  }

  void reload() => setState(() => _future = _load(force: true));

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
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
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _to = picked;
        _outstandingPage = 1;
        _future = _load(force: true);
      });
    }
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
      if (mounted) {
        _toast(context, reportErrorMessage(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickFrom,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _from == null ? 'From' : _ymd(_from!),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickTo,
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(_to == null ? 'To' : _ymd(_to!)),
                  ),
                  if (_from != null || _to != null || _wingCode != null)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _from = null;
                          _to = null;
                          _wingCode = null;
                          _outstandingPage = 1;
                          _future = _load(force: true);
                        });
                      },
                      child: const Text('Clear filters'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('All wings'),
                    selected: _wingCode == null,
                    onSelected: (_) {
                      setState(() {
                        _wingCode = null;
                        _outstandingPage = 1;
                        _future = _load(force: true);
                      });
                    },
                  ),
                  for (final w in _wings)
                    FilterChip(
                      label: Text(w.code),
                      selected: _wingCode == w.code,
                      onSelected: (_) {
                        setState(() {
                          _wingCode = w.code;
                          _outstandingPage = 1;
                          _future = _load(force: true);
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: C.blue,
          unselectedLabelColor: C.muted,
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'Financial'),
            Tab(text: 'Collections'),
            Tab(text: 'Outstanding'),
            Tab(text: 'Complaints'),
          ],
        ),
        Expanded(
          child: FutureBuilder<_ReportsBundle>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const LoadingView(label: 'Loading reports…');
              }
              if (snap.hasError) {
                return LoadFailure(error: snap.error!, onRetry: reload);
              }
              final b = snap.data!;
              return TabBarView(
                controller: _tabs,
                children: [
                  _dashboardTab(b),
                  _financialTab(b.financial),
                  _collectionsTab(b.collections),
                  _outstandingTab(b.outstanding),
                  _complaintsTab(b.complaints),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _dashboardTab(_ReportsBundle b) {
    final fin = b.dashboard.financial;
    final col = b.dashboard.collections;
    final soc = b.society.totals;
    final cmp = b.dashboard.complaints;
    return RefreshIndicator(
      color: C.blue,
      onRefresh: () async {
        reload();
        await _future;
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Period ${b.dashboard.from.substring(0, 10)} → '
            '${b.dashboard.to.substring(0, 10)}'
            '${b.dashboard.wingCode != null ? ' · Wing ${b.dashboard.wingCode}' : ''}',
            style: const TextStyle(color: C.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          const SectionTitle('Society inventory'),
          const SizedBox(height: 8),
          StatCard(
            title: 'Total flats',
            value: '${soc.flats}',
            icon: Icons.apartment_outlined,
          ),
          const SizedBox(height: 10),
          StatCard(
            title: 'Occupied / vacant',
            value:
                '${soc.ownerOccupiedFlats + soc.tenantOccupiedFlats} / ${soc.vacantFlats}',
            icon: Icons.home_work_outlined,
          ),
          const SizedBox(height: 10),
          StatCard(
            title: 'Monthly maintenance (rate sum)',
            // Society dashboard totals are whole-rupee integers (maintenanceRate),
            // not paise — match Admin dashboard formatting.
            value: money(soc.monthlyMaintenanceTotal),
            icon: Icons.account_balance_wallet_outlined,
          ),
          const SizedBox(height: 16),
          const SectionTitle('Financial snapshot'),
          const SizedBox(height: 8),
          StatCard(
            title: 'Total billed',
            value: moneyPaise(fin.totalBilledPaise),
            icon: Icons.receipt_long_outlined,
          ),
          const SizedBox(height: 10),
          StatCard(
            title: 'Collected',
            value: moneyPaise(fin.totalCollectedPaise),
            icon: Icons.payments_outlined,
            accent: C.green,
          ),
          const SizedBox(height: 10),
          StatCard(
            title: 'Outstanding principal',
            value: moneyPaise(
              b.dashboard.outstandingTotals.outstandingPrincipalPaise,
            ),
            icon: Icons.pending_actions_outlined,
            accent: C.amber,
          ),
          const SizedBox(height: 10),
          StatCard(
            title: 'Accrued interest',
            value: moneyPaise(fin.totalAccruedInterestPaise),
            icon: Icons.percent_outlined,
          ),
          const SizedBox(height: 16),
          const SectionTitle('Collections snapshot'),
          const SizedBox(height: 8),
          billDetailLine('Bills generated', '${col.totalBillsGenerated}'),
          billDetailLine('Paid / partial / unpaid / overdue',
              '${col.paidBills} / ${col.partiallyPaidBills} / ${col.unpaidBills} / ${col.overdueBills}'),
          billDetailLine(
            'Collection %',
            '${col.collectionPercentage.toStringAsFixed(1)}%',
          ),
          const SizedBox(height: 16),
          const SectionTitle('Complaints snapshot'),
          const SizedBox(height: 8),
          billDetailLine('Total', '${cmp.totalComplaints}'),
          billDetailLine(
            'Open / assigned / in progress',
            '${cmp.open} / ${cmp.assigned} / ${cmp.inProgress}',
          ),
          billDetailLine(
            'Resolved / closed / cancelled',
            '${cmp.resolved} / ${cmp.closed} / ${cmp.cancelled}',
          ),
          if (b.dashboard.topFlats.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionTitle('Top outstanding flats'),
            const SizedBox(height: 8),
            ...b.dashboard.topFlats.map(
              (f) => AppCard(
                child: ListTile(
                  title: Text(
                    '${f.flatNumber} · ${f.wingCode}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${f.ownerNameSnapshot}\n'
                    'Principal ${moneyPaise(f.outstandingPrincipalPaise)} · '
                    'Interest ${moneyPaise(f.accruedInterestPaise)}',
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const SectionTitle('Export CSV'),
          const SizedBox(height: 8),
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final type in reportExportTypes)
              QuickActionTile(
                icon: Icons.download_outlined,
                label: 'Export $type',
                onTap: () => _export(
                  type,
                  from: b.dashboard.from,
                  to: b.dashboard.to,
                ),
              ),
        ],
      ),
    );
  }

  Widget _financialTab(FinancialReport r) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${r.from.substring(0, 10)} → ${r.to.substring(0, 10)}',
          style: const TextStyle(color: C.muted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        billDetailLine('Billed', moneyPaise(r.totalBilledPaise)),
        billDetailLine('Collected', moneyPaise(r.totalCollectedPaise)),
        billDetailLine(
          'Outstanding principal',
          moneyPaise(r.totalOutstandingPrincipalPaise),
        ),
        billDetailLine(
          'Accrued interest',
          moneyPaise(r.totalAccruedInterestPaise),
        ),
        billDetailLine('Refunds', moneyPaise(r.totalRefundsPaise)),
        billDetailLine(
          'Offline collections',
          moneyPaise(r.totalOfflineCollectionsPaise),
        ),
        billDetailLine(
          'Online collections',
          moneyPaise(r.totalOnlineCollectionsPaise),
        ),
        billDetailLine(
          'Payments success / fail / refunded / pending',
          '${r.paymentSuccessCount} / ${r.paymentFailureCount} / '
          '${r.paymentRefundedCount} / ${r.paymentPendingCount}',
        ),
        billDetailLine('Bills', '${r.billCount}'),
        billDetailLine(
          'Collection %',
          '${r.collectionPercentage.toStringAsFixed(1)}%',
        ),
        const SizedBox(height: 8),
        InfoNote(r.note),
        if (r.monthly.isNotEmpty) ...[
          const SizedBox(height: 16),
          const SectionTitle('Monthly'),
          const SizedBox(height: 8),
          ...r.monthly.map(
            (m) => AppCard(
              child: ListTile(
                title: Text(
                  '${m.year}-${(m.month ?? 0).toString().padLeft(2, '0')}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Billed ${moneyPaise(m.billedPaise)} · '
                  'Collected ${moneyPaise(m.collectedPaise)} · '
                  'Outstanding ${moneyPaise(m.outstandingPrincipalPaise)}',
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _exporting
              ? null
              : () => _export('financial', from: r.from, to: r.to),
          icon: const Icon(Icons.download),
          label: const Text('Export financial CSV'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _exporting
              ? null
              : () => _export('payments', from: r.from, to: r.to),
          icon: const Icon(Icons.payments_outlined),
          label: const Text('Export payments CSV'),
        ),
      ],
    );
  }

  Widget _collectionsTab(CollectionReport r) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        billDetailLine('Bills generated', '${r.totalBillsGenerated}'),
        billDetailLine('Billed', moneyPaise(r.totalBilledPaise)),
        billDetailLine('Collected', moneyPaise(r.totalAmountCollectedPaise)),
        billDetailLine(
          'Outstanding',
          moneyPaise(r.totalAmountOutstandingPaise),
        ),
        billDetailLine('Paid bills', '${r.paidBills}'),
        billDetailLine('Partially paid', '${r.partiallyPaidBills}'),
        billDetailLine('Unpaid', '${r.unpaidBills}'),
        billDetailLine('Overdue', '${r.overdueBills}'),
        billDetailLine(
          'Collection %',
          '${r.collectionPercentage.toStringAsFixed(1)}%',
        ),
        Text(
          r.collectionPercentageFormula,
          style: const TextStyle(color: C.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        const SectionTitle('By wing'),
        const SizedBox(height: 8),
        if (r.wingWise.isEmpty)
          const EmptyState('No wing collection data')
        else
          ...r.wingWise.map(
            (w) => AppCard(
              child: ListTile(
                title: Text(
                  'Wing ${w.wingCode}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Billed ${moneyPaise(w.billedPaise)} · '
                  'Collected ${moneyPaise(w.collectedPaise)} · '
                  'Outstanding ${moneyPaise(w.outstandingPrincipalPaise)} · '
                  '${w.collectionPercentage.toStringAsFixed(1)}%',
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _exporting
              ? null
              : () => _export('collections', from: r.from, to: r.to),
          icon: const Icon(Icons.download),
          label: const Text('Export collections CSV'),
        ),
      ],
    );
  }

  Widget _outstandingTab(OutstandingReport r) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        billDetailLine(
          'Principal',
          moneyPaise(r.outstandingPrincipalPaise),
        ),
        billDetailLine('Interest', moneyPaise(r.accruedInterestPaise)),
        billDetailLine('Flats', '${r.flatCount}'),
        const SizedBox(height: 12),
        if (r.items.isEmpty)
          const EmptyState('No outstanding flats')
        else
          ...r.items.map(
            (f) => AppCard(
              child: ListTile(
                title: Text(
                  '${f.flatNumber} · ${f.wingCode}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${f.ownerNameSnapshot}\n'
                  'Billed ${moneyPaise(f.billedPaise)} · '
                  'Collected ${moneyPaise(f.collectedPaise)}\n'
                  'Principal ${moneyPaise(f.outstandingPrincipalPaise)} · '
                  'Interest ${moneyPaise(f.accruedInterestPaise)}',
                ),
                isThreeLine: true,
              ),
            ),
          ),
        if (r.pagination.totalPages > 1) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Page ${r.pagination.page} of ${r.pagination.totalPages}',
                style: const TextStyle(color: C.muted),
              ),
              const Spacer(),
              TextButton(
                onPressed: r.pagination.page <= 1
                    ? null
                    : () {
                        setState(() {
                          _outstandingPage = r.pagination.page - 1;
                          _future = _load(force: true);
                        });
                      },
                child: const Text('Prev'),
              ),
              TextButton(
                onPressed: r.pagination.page >= r.pagination.totalPages
                    ? null
                    : () {
                        setState(() {
                          _outstandingPage = r.pagination.page + 1;
                          _future = _load(force: true);
                        });
                      },
                child: const Text('Next'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _exporting
              ? null
              : () => _export('outstanding', from: r.from, to: r.to),
          icon: const Icon(Icons.download),
          label: const Text('Export outstanding CSV'),
        ),
      ],
    );
  }

  Widget _complaintsTab(ComplaintReport r) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        billDetailLine('Total', '${r.totalComplaints}'),
        billDetailLine('Open', '${r.open}'),
        billDetailLine('Assigned', '${r.assigned}'),
        billDetailLine('In progress', '${r.inProgress}'),
        billDetailLine('Resolved', '${r.resolved}'),
        billDetailLine('Closed', '${r.closed}'),
        billDetailLine('Cancelled', '${r.cancelled}'),
        if (r.averageResolutionHours != null)
          billDetailLine(
            'Avg resolution hours',
            r.averageResolutionHours!.toStringAsFixed(1),
          ),
        const SizedBox(height: 12),
        const SectionTitle('By category'),
        ...r.byCategory.entries.map(
          (e) => billDetailLine(e.key, '${e.value}'),
        ),
        const SizedBox(height: 12),
        const SectionTitle('By priority'),
        ...r.byPriority.entries.map(
          (e) => billDetailLine(e.key, '${e.value}'),
        ),
        if (r.byWing.isNotEmpty) ...[
          const SizedBox(height: 12),
          const SectionTitle('By wing'),
          ...r.byWing.map(
            (w) => billDetailLine('Wing ${w.wingCode}', '${w.count}'),
          ),
        ],
        if (r.workload.isNotEmpty) ...[
          const SizedBox(height: 12),
          const SectionTitle('Workload'),
          ...r.workload.map(
            (w) => billDetailLine(w.assignedToName, '${w.openAssigned} open'),
          ),
        ],
        const SizedBox(height: 8),
        InfoNote(r.note),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _exporting
              ? null
              : () => _export('complaints', from: r.from, to: r.to),
          icon: const Icon(Icons.download),
          label: const Text('Export complaints CSV'),
        ),
      ],
    );
  }
}

class _ReportsBundle {
  const _ReportsBundle({
    required this.society,
    required this.dashboard,
    required this.financial,
    required this.collections,
    required this.outstanding,
    required this.complaints,
  });

  final DashboardStats society;
  final ReportsDashboard dashboard;
  final FinancialReport financial;
  final CollectionReport collections;
  final OutstandingReport outstanding;
  final ComplaintReport complaints;
}
