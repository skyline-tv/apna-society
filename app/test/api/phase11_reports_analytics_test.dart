import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/report_models.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:apna_society/api/repositories/report_repository.dart';
import 'package:apna_society/features/reports/live_reports_module.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(clearLiveRepositories);

  group('Report model parsing', () {
    test('parses financial report money fields as integers', () {
      final r = FinancialReport.fromJson(_financial());
      expect(r.totalBilledPaise, 1200000);
      expect(r.totalCollectedPaise, 200000);
      expect(r.totalOutstandingPrincipalPaise, 1000000);
      expect(r.totalAccruedInterestPaise, 1500);
      expect(r.totalRefundsPaise, 0);
      expect(r.totalOfflineCollectionsPaise, 200000);
      expect(r.totalOnlineCollectionsPaise, 0);
      expect(r.paymentSuccessCount, 1);
      expect(r.collectionPercentage, 16.67);
      expect(r.monthly, hasLength(1));
      expect(r.monthly.first.billedPaise, 1200000);
      expect(r.note, isNotEmpty);
    });

    test('parses collection report with wing-wise breakdown', () {
      final r = CollectionReport.fromJson(_collections());
      expect(r.totalBillsGenerated, 3);
      expect(r.totalBilledPaise, 1200000);
      expect(r.totalAmountCollectedPaise, 200000);
      expect(r.totalAmountOutstandingPaise, 1000000);
      expect(r.paidBills, 0);
      expect(r.partiallyPaidBills, 1);
      expect(r.unpaidBills, 2);
      expect(r.overdueBills, 0);
      expect(r.wingWise, hasLength(1));
      expect(r.wingWise.first.wingCode, 'A');
      expect(r.collectionPercentageFormula, contains('collected'));
    });

    test('parses outstanding report with pagination totals', () {
      final r = OutstandingReport.fromJson(_outstanding());
      expect(r.outstandingPrincipalPaise, 1000000);
      expect(r.accruedInterestPaise, 1500);
      expect(r.flatCount, 2);
      expect(r.items, hasLength(1));
      expect(r.items.first.flatNumber, 'A-101');
      expect(r.items.first.outstandingPrincipalPaise, 200000);
      expect(r.pagination.page, 1);
      expect(r.pagination.totalPages, 1);
    });

    test('parses complaint report maps and workload', () {
      final r = ComplaintReport.fromJson(_complaints());
      expect(r.totalComplaints, 5);
      expect(r.open, 1);
      expect(r.byCategory['PLUMBING'], 2);
      expect(r.byPriority['HIGH'], 1);
      expect(r.byWing.first.wingCode, 'A');
      expect(r.workload.first.assignedToName, 'Staff One');
      expect(r.averageResolutionHours, 12.5);
    });

    test('parses typed reports dashboard', () {
      final d = ReportsDashboard.fromJson(_dashboard());
      expect(d.from, startsWith('2026-07-01'));
      expect(d.financial.totalBilledPaise, 1200000);
      expect(d.collections.paidBills, 0);
      expect(d.outstandingTotals.outstandingPrincipalPaise, 1000000);
      expect(d.topFlats, hasLength(1));
      expect(d.complaints.totalComplaints, 5);
      expect(d.wingCode, isNull);
    });

    test('rejects non-integer billed paise', () {
      expect(
        () => FinancialReport.fromJson({
          ..._financial(),
          'totalBilledPaise': 12.5,
        }),
        throwsA(isA<ApiParseException>()),
      );
    });
  });

  group('CSV filename', () {
    test('builds sensible names from type and date range', () {
      expect(reportCsvFilename(type: 'financial'), 'financial-report.csv');
      expect(
        reportCsvFilename(
          type: 'payments',
          from: '2026-07-01T00:00:00.000Z',
          to: '2026-07-01T23:59:59.000Z',
        ),
        'payments-report-2026-07-01.csv',
      );
      expect(
        reportCsvFilename(
          type: 'collections',
          from: '2026-07-01T00:00:00.000Z',
          to: '2026-09-30T00:00:00.000Z',
        ),
        'collections-report-2026-07-01-to-2026-09-30.csv',
      );
    });
  });

  group('Report API paths and filters', () {
    test('dashboard path and wing/date query params', () async {
      late RequestOptions seen;
      final adapter = ScriptedAdapter((options) async {
        seen = options;
        return jsonBody(200, {'success': true, 'data': _dashboard()});
      });
      final repo = ReportRepository(_api(adapter).reports);
      await repo.dashboard(
        query: const ReportQuery(
          from: '2026-07-01T00:00:00.000Z',
          to: '2026-09-30T00:00:00.000Z',
          wingCode: 'A',
        ),
      );
      expect(seen.path.endsWith('/admin/reports/dashboard'), isTrue);
      expect(seen.queryParameters['from'], '2026-07-01T00:00:00.000Z');
      expect(seen.queryParameters['to'], '2026-09-30T00:00:00.000Z');
      expect(seen.queryParameters['wingCode'], 'A');
    });

    test('financial, collections, outstanding, complaints paths', () async {
      final paths = <String>[];
      final adapter = ScriptedAdapter((options) async {
        paths.add(options.path);
        if (options.path.endsWith('/financial')) {
          return jsonBody(200, {'success': true, 'data': _financial()});
        }
        if (options.path.endsWith('/collections')) {
          return jsonBody(200, {'success': true, 'data': _collections()});
        }
        if (options.path.endsWith('/outstanding')) {
          expect('${options.queryParameters['page']}', '2');
          expect('${options.queryParameters['limit']}', '50');
          return jsonBody(200, {'success': true, 'data': _outstanding()});
        }
        if (options.path.endsWith('/complaints')) {
          return jsonBody(200, {'success': true, 'data': _complaints()});
        }
        return notFound(options.path);
      });
      final repo = ReportRepository(_api(adapter).reports);
      const q = ReportQuery(page: 2, limit: 50, wingCode: 'B');
      await repo.financial(query: q);
      await repo.collections(query: q);
      await repo.outstanding(query: q);
      await repo.complaints(query: q);
      expect(paths.any((p) => p.endsWith('/admin/reports/financial')), isTrue);
      expect(paths.any((p) => p.endsWith('/admin/reports/collections')), isTrue);
      expect(paths.any((p) => p.endsWith('/admin/reports/outstanding')), isTrue);
      expect(paths.any((p) => p.endsWith('/admin/reports/complaints')), isTrue);
    });

    test('payment method and status forwarded on financial query', () async {
      late RequestOptions seen;
      final adapter = ScriptedAdapter((options) async {
        seen = options;
        return jsonBody(200, {'success': true, 'data': _financial()});
      });
      final repo = ReportRepository(_api(adapter).reports);
      await repo.financial(
        query: const ReportQuery(
          paymentMethod: 'UPI',
          paymentStatus: 'SUCCESS',
        ),
      );
      expect(seen.queryParameters['paymentMethod'], 'UPI');
      expect(seen.queryParameters['paymentStatus'], 'SUCCESS');
    });
  });

  group('CSV export', () {
    test('downloads actual CSV bytes with format=csv', () async {
      late RequestOptions seen;
      final csv = Uint8List.fromList(utf8.encode('wing,billed\nA,1200000\n'));
      final adapter = ScriptedAdapter((options) async {
        seen = options;
        return ResponseBody.fromBytes(
          csv,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/csv'],
          },
        );
      });
      final repo = ReportRepository(_api(adapter).reports);
      final bytes = await repo.exportCsv(
        'financial',
        query: const ReportQuery(
          from: '2026-07-01T00:00:00.000Z',
          to: '2026-09-30T00:00:00.000Z',
        ),
      );
      expect(seen.path.endsWith('/admin/reports/export/financial'), isTrue);
      expect(seen.queryParameters['format'], 'csv');
      expect(seen.queryParameters['from'], '2026-07-01T00:00:00.000Z');
      expect(utf8.decode(bytes), 'wing,billed\nA,1200000\n');
    });

    test('rejects unknown export type without calling network', () async {
      var called = false;
      final adapter = ScriptedAdapter((options) async {
        called = true;
        return notFound(options.path);
      });
      final repo = ReportRepository(_api(adapter).reports);
      await expectLater(
        repo.exportCsv('ledger'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'INVALID_EXPORT_TYPE',
          ),
        ),
      );
      expect(called, isFalse);
    });

    test('surfaces export HTTP failures', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(500, {
          'success': false,
          'error': {'code': 'INTERNAL_ERROR', 'message': 'export failed'},
        });
      });
      final repo = ReportRepository(_api(adapter).reports);
      await expectLater(
        repo.exportCsv('payments'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('Cache and mutations', () {
    test('caches by query key and force reloads', () async {
      var hits = 0;
      final adapter = ScriptedAdapter((options) async {
        hits++;
        return jsonBody(200, {'success': true, 'data': _financial()});
      });
      final repo = ReportRepository(_api(adapter).reports);
      const q1 = ReportQuery(wingCode: 'A');
      const q2 = ReportQuery(wingCode: 'B');
      await repo.financial(query: q1);
      await repo.financial(query: q1);
      expect(hits, 1);
      await repo.financial(query: q2);
      expect(hits, 2);
      await repo.financial(query: q1, force: true);
      expect(hits, 3);
    });

    test('clear on logout and financial/complaint invalidation', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/financial')) {
          return jsonBody(200, {'success': true, 'data': _financial()});
        }
        if (options.path.endsWith('/complaints') &&
            options.path.contains('/admin/reports/')) {
          return jsonBody(200, {'success': true, 'data': _complaints()});
        }
        return notFound(options.path);
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.reports.financial();
      await repos.reports.complaints();
      repos.invalidateAfterFinancialMutation();
      var hits = 0;
      final adapter2 = ScriptedAdapter((options) async {
        hits++;
        if (options.path.endsWith('/financial')) {
          return jsonBody(200, {'success': true, 'data': _financial()});
        }
        return jsonBody(200, {'success': true, 'data': _complaints()});
      });
      // Replace by clearing and recreating with new adapter is awkward;
      // instead verify clear() empties cache via force-free second call needing network.
      clearLiveRepositories();
      final repos2 = ensureLiveRepositories(_api(adapter2));
      await repos2.reports.financial();
      expect(hits, 1);
      await repos2.reports.financial();
      expect(hits, 1);
      repos2.invalidateAfterComplaintMutation();
      await repos2.reports.financial();
      expect(hits, 2);
    });
  });

  group('Role and error handling', () {
    test('FORBIDDEN_ROLE surfaces for non-admin', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {
            'code': 'FORBIDDEN_ROLE',
            'message': 'Admin only',
          },
        });
      });
      final repo = ReportRepository(_api(adapter).reports);
      await expectLater(
        repo.dashboard(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'FORBIDDEN_ROLE',
          ),
        ),
      );
      expect(
        reportErrorMessage(
          ApiException(code: 'FORBIDDEN_ROLE', message: 'Admin only'),
        ),
        'You do not have access to admin reports.',
      );
    });

    test('expired session surfaces UNAUTHORIZED', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(401, {
          'success': false,
          'error': {
            'code': 'UNAUTHORIZED',
            'message': 'Token expired',
          },
        });
      });
      final repo = ReportRepository(_api(adapter).reports);
      await expectLater(
        repo.collections(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'UNAUTHORIZED',
          ),
        ),
      );
    });
  });

  group('Export type allow-list', () {
    test('supports backend export types including payments and complaints', () {
      expect(
        reportExportTypes,
        containsAll([
          'financial',
          'collections',
          'outstanding',
          'payments',
          'complaints',
        ]),
      );
    });
  });
}

ApnaApi _api(ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4000'));
  dio.httpClientAdapter = adapter;
  final client = ApiClient(
    config: ApiConfig.resolve(flavorName: 'development'),
    dio: dio,
  );
  client.societyId = societyId;
  return ApnaApi(client: client);
}

const societyId = '507f1f77bcf86cd799439011';
const flatId = '507f1f77bcf86cd799439013';

Map<String, Object?> _financial() => {
      'from': '2026-07-01T00:00:00.000Z',
      'to': '2026-09-30T23:59:59.000Z',
      'totalBilledPaise': 1200000,
      'totalCollectedPaise': 200000,
      'totalOutstandingPrincipalPaise': 1000000,
      'totalAccruedInterestPaise': 1500,
      'totalRefundsPaise': 0,
      'totalOfflineCollectionsPaise': 200000,
      'totalOnlineCollectionsPaise': 0,
      'paymentSuccessCount': 1,
      'paymentFailureCount': 0,
      'paymentRefundedCount': 0,
      'paymentPendingCount': 0,
      'billCount': 3,
      'collectionPercentage': 16.67,
      'monthly': [
        {
          'year': 2026,
          'month': 8,
          'billedPaise': 1200000,
          'collectedPaise': 200000,
          'outstandingPrincipalPaise': 1000000,
          'billCount': 3,
          'collectionPercentage': 16.67,
        },
      ],
      'yearly': [
        {
          'year': 2026,
          'billedPaise': 1200000,
          'collectedPaise': 200000,
          'outstandingPrincipalPaise': 1000000,
          'billCount': 3,
        },
      ],
      'note': 'Totals are computed by the server in integer paise.',
    };

Map<String, Object?> _collections() => {
      'from': '2026-07-01T00:00:00.000Z',
      'to': '2026-09-30T23:59:59.000Z',
      'totalBillsGenerated': 3,
      'totalAmountCollectedPaise': 200000,
      'totalAmountOutstandingPaise': 1000000,
      'totalBilledPaise': 1200000,
      'paidBills': 0,
      'partiallyPaidBills': 1,
      'unpaidBills': 2,
      'overdueBills': 0,
      'collectionPercentage': 16.67,
      'collectionPercentageFormula':
          'collectionPercentage = collected / billed * 100',
      'wingWise': [
        {
          'wingCode': 'A',
          'billedPaise': 900000,
          'collectedPaise': 200000,
          'outstandingPrincipalPaise': 700000,
          'billCount': 2,
          'collectionPercentage': 22.22,
        },
      ],
      'monthlyTrends': [
        {
          'year': 2026,
          'month': 8,
          'billedPaise': 1200000,
          'collectedPaise': 200000,
          'outstandingPrincipalPaise': 1000000,
          'billCount': 3,
        },
      ],
    };

Map<String, Object?> _outstandingFlat() => {
      'flatId': flatId,
      'wingCode': 'A',
      'flatNumber': 'A-101',
      'ownerNameSnapshot': 'Owner One',
      'billedPaise': 400000,
      'collectedPaise': 200000,
      'outstandingPrincipalPaise': 200000,
      'accruedInterestPaise': 500,
      'billCount': 1,
    };

Map<String, Object?> _outstanding() => {
      'from': '2026-07-01T00:00:00.000Z',
      'to': '2026-09-30T23:59:59.000Z',
      'items': [_outstandingFlat()],
      'totals': {
        'outstandingPrincipalPaise': 1000000,
        'accruedInterestPaise': 1500,
        'flatCount': 2,
      },
      'pagination': {
        'page': 1,
        'limit': 50,
        'total': 2,
        'totalPages': 1,
      },
    };

Map<String, Object?> _complaints() => {
      'from': '2026-07-01T00:00:00.000Z',
      'to': '2026-09-30T23:59:59.000Z',
      'totalComplaints': 5,
      'open': 1,
      'assigned': 1,
      'inProgress': 1,
      'resolved': 1,
      'closed': 1,
      'cancelled': 0,
      'byCategory': {'PLUMBING': 2, 'ELECTRICAL': 3},
      'byPriority': {'HIGH': 1, 'MEDIUM': 4},
      'byWing': [
        {'wingCode': 'A', 'count': 3},
      ],
      'averageResolutionHours': 12.5,
      'resolvedWithTimestampCount': 1,
      'trends': [
        {'year': 2026, 'month': 8, 'count': 5},
      ],
      'workload': [
        {
          'assignedToUserId': '507f1f77bcf86cd799439099',
          'assignedToName': 'Staff One',
          'openAssigned': 2,
        },
      ],
      'note':
          'averageResolutionHours uses resolvedAt - createdAt only when resolvedAt is present.',
    };

Map<String, Object?> _dashboard() => {
      'from': '2026-07-01T00:00:00.000Z',
      'to': '2026-09-30T23:59:59.000Z',
      'financial': {
        'totalBilledPaise': 1200000,
        'totalCollectedPaise': 200000,
        'totalOutstandingPrincipalPaise': 1000000,
        'totalAccruedInterestPaise': 1500,
        'totalRefundsPaise': 0,
        'totalOfflineCollectionsPaise': 200000,
        'totalOnlineCollectionsPaise': 0,
        'paymentSuccessCount': 1,
        'paymentFailureCount': 0,
        'collectionPercentage': 16.67,
      },
      'collections': {
        'totalBillsGenerated': 3,
        'paidBills': 0,
        'partiallyPaidBills': 1,
        'unpaidBills': 2,
        'overdueBills': 0,
        'collectionPercentage': 16.67,
        'wingWise': [
          {
            'wingCode': 'A',
            'billedPaise': 900000,
            'collectedPaise': 200000,
            'outstandingPrincipalPaise': 700000,
            'billCount': 2,
            'collectionPercentage': 22.22,
          },
        ],
      },
      'outstanding': {
        'totals': {
          'outstandingPrincipalPaise': 1000000,
          'accruedInterestPaise': 1500,
          'flatCount': 2,
        },
        'topFlats': [_outstandingFlat()],
      },
      'complaints': {
        'totalComplaints': 5,
        'open': 1,
        'assigned': 1,
        'inProgress': 1,
        'resolved': 1,
        'closed': 1,
        'cancelled': 0,
        'averageResolutionHours': 12.5,
        'byCategory': {'PLUMBING': 2},
      },
    };

ResponseBody notFound(String path) => jsonBody(404, {
      'success': false,
      'error': {'code': 'ROUTE_NOT_FOUND', 'message': path},
    });

ResponseBody jsonBody(int status, Object payload) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this._handler);
  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
