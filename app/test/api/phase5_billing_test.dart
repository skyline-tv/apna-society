import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/billing_models.dart';
import 'package:apna_society/api/repositories/billing_repository.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:apna_society/app_core.dart';
import 'package:apna_society/features/billing/live_additional_services_module.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const societyId = '507f1f77bcf86cd799439011';
  const billId = '507f1f77bcf86cd799439041';
  const flatId = '507f1f77bcf86cd799439013';

  tearDown(clearLiveRepositories);

  group('moneyPaise', () {
    test('formats integer paise as rupees with two decimals', () {
      expect(moneyPaise(0), '₹0.00');
      expect(moneyPaise(100), '₹1.00');
      expect(moneyPaise(123456), '₹1,234.56');
      expect(moneyPaise(-250), '-₹2.50');
    });
  });

  group('Admin billing', () {
    test('lists bills and maps detail fields', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/billing/bills') && options.method == 'GET') {
          return jsonBody(200, {
            'success': true,
            'data': {
              'items': [_bill(billId, flatId)],
              'pagination': {
                'page': 1,
                'limit': 20,
                'total': 1,
                'totalPages': 1,
              },
            },
          });
        }
        return notFound(options.path);
      });
      final repo = BillingRepository(_api(adapter).billing);
      final page = await repo.listAdminBills();
      expect(page.items, hasLength(1));
      expect(page.items.first.billNumber, 'BILL-2026-000001');
      expect(page.items.first.outstandingPrincipalPaise, 400000);
      expect(billAmountDuePaise(page.items.first), 400000 + 1200);
    });

    test('generates 1-month and 3-month bills', () async {
      for (final months in [1, 3]) {
        final adapter = ScriptedAdapter((options) async {
          expect(options.path.endsWith('/billing/generate'), isTrue);
          expect(options.data['numberOfMonths'], months);
          expect(options.data['dueDate'], '2026-04-20T00:00:00.000+05:30');
          return jsonBody(201, {
            'success': true,
            'data': {
              'periodStart': '2026-04-01T00:00:00.000Z',
              'periodEnd': '2026-04-30T00:00:00.000Z',
              'dueDate': '2026-04-10T00:00:00.000Z',
              'numberOfMonths': months,
              'createdCount': 1,
              'skippedCount': 0,
              'conflictCount': 0,
              'totalBilledPaise': 400000 * months,
              'created': [_bill(billId, flatId)],
              'skipped': <Object>[],
              'conflicts': <Object>[],
            },
          });
        });
        final repo = BillingRepository(_api(adapter).billing);
        final result = await repo.generateBills(
          billingPeriodStart: '2026-04-01T00:00:00.000Z',
          numberOfMonths: months,
          dueDate: '2026-04-20T00:00:00.000+05:30',
        );
        expect(result.createdCount, 1);
        expect(result.numberOfMonths, months);
      }
    });

    test('omits dueDate so the server defaults to the 10th', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/billing/generate'), isTrue);
        expect(options.data.containsKey('dueDate'), isFalse);
        return jsonBody(201, {
          'success': true,
          'data': {
            'periodStart': '2026-04-01T00:00:00.000Z',
            'periodEnd': '2026-04-30T00:00:00.000Z',
            'dueDate': '2026-04-10T18:29:59.999Z',
            'numberOfMonths': 1,
            'createdCount': 1,
            'skippedCount': 0,
            'conflictCount': 0,
            'totalBilledPaise': 400000,
            'created': [_bill(billId, flatId)],
            'skipped': <Object>[],
            'conflicts': <Object>[],
          },
        });
      });
      final repo = BillingRepository(_api(adapter).billing);
      final result = await repo.generateBills(
        billingPeriodStart: '2026-04-01T00:00:00.000Z',
        numberOfMonths: 1,
      );
      expect(result.createdCount, 1);
    });

    test('parses unassigned bills and additional service line items', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/billing/bills'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [
              {
                ..._bill(billId, flatId),
                'ownerUserId': null,
                'ownerAssigned': false,
                'ownerNameSnapshot': 'Unassigned',
                'additionalServicesTotalPaise': 50000,
                'totalAmountPaise': 450000,
                'lineItems': [
                  {
                    'type': 'MAINTENANCE',
                    'name': 'Monthly maintenance',
                    'quantity': 1,
                    'unitAmountPaise': 400000,
                    'amountPaise': 400000,
                  },
                  {
                    'type': 'ADDITIONAL_SERVICE',
                    'name': 'Additional car parking',
                    'quantity': 1,
                    'unitAmountPaise': 50000,
                    'amountPaise': 50000,
                  },
                ],
              },
            ],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = BillingRepository(_api(adapter).billing);
      final page = await repo.listAdminBills();
      expect(page.items.first.ownerUserId, isNull);
      expect(page.items.first.ownerAssigned, isFalse);
      expect(page.items.first.additionalServicesTotalPaise, 50000);
      expect(page.items.first.lineItems, hasLength(2));
      expect(page.items.first.lineItems.last.name, 'Additional car parking');
    });

    test('total payable is principal plus accrued interest', () {
      final bill = Bill.fromJson({
        ..._bill(billId, flatId),
        'interestAccruedPaise': 1200,
        'totalPayablePaise': 401200,
      });
      expect(billAmountDuePaise(bill), 401200);
      expect(
        billAmountDuePaise(bill),
        bill.outstandingPrincipalPaise + bill.interestAccruedPaise,
      );
      expect(
        billingSummaryPayablePaise(
          BillingSummary(
            totalBilledPaise: 400000,
            totalCollectedPaise: 0,
            totalOutstandingPrincipalPaise: 400000,
            totalAccruedInterestPaise: 1200,
            paidBills: 0,
            partiallyPaidBills: 0,
            overdueBills: 1,
            issuedBills: 0,
            cancelledBills: 0,
            vacantOrUnassignedFlatsSkipped: 0,
            collectionPercentage: 0,
            billCount: 1,
            wingWise: const [],
            paymentsByStatus: const {},
          ),
        ),
        401200,
      );
    });

    test('paid bill outstanding is zero even if accrued interest remains', () {
      final bill = Bill.fromJson({
        ..._bill(billId, flatId, status: 'PAID'),
        'outstandingPrincipalPaise': 0,
        'amountPaidPaise': 400000,
        'interestAccruedPaise': 1200,
        'totalPayablePaise': 1200,
      });
      expect(billAmountDuePaise(bill), 0);
      expect(bill.status, 'PAID');
    });

    test('civilDateToIso uses IST midnight not UTC shift', () {
      expect(
        civilDateToIso(DateTime(2026, 4, 15)),
        '2026-04-15T00:00:00.000+05:30',
      );
    });

    test('enforces a 10-active-services-per-flat cap in models and API', () {
      AdditionalService serviceAt(int i, {bool active = true}) {
        return AdditionalService.fromJson({
          ..._service(flatId),
          'id': '507f1f77bcf86cd7994390${i.toString().padLeft(2, '0')}',
          'name': 'Service $i',
          'isActive': active,
        });
      }

      expect(kMaxActiveAdditionalServicesPerFlat, 10);
      expect(
        canAddActiveAdditionalService(List.generate(9, serviceAt)),
        isTrue,
      );
      expect(
        canAddActiveAdditionalService(List.generate(10, serviceAt)),
        isFalse,
      );
      expect(
        canAddActiveAdditionalService([
          ...List.generate(10, (i) => serviceAt(i, active: false)),
          ...List.generate(9, (i) => serviceAt(20 + i)),
        ]),
        isTrue,
      );
      expect(
        additionalServiceError(ApiException(
          code: kAdditionalServiceLimitCode,
          message: 'ignored',
        )),
        kAdditionalServiceLimitMessage,
      );
    });

    test('maps ADDITIONAL_SERVICE_LIMIT from create', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': kAdditionalServiceLimitCode,
            'message': kAdditionalServiceLimitMessage,
          },
        });
      });
      final repo = BillingRepository(_api(adapter).billing);
      expect(
        () => repo.createAdditionalService(
          const CreateAdditionalServiceRequest(
            flatId: flatId,
            name: 'Eleventh',
            monthlyChargePaise: 1000,
            quantity: 1,
            effectiveFrom: '2026-04-01T00:00:00.000Z',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            kAdditionalServiceLimitCode,
          ),
        ),
      );
    });

    test('creates and lists additional services', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.method == 'POST' &&
            options.path.endsWith('/billing/additional-services')) {
          return jsonBody(201, {
            'success': true,
            'data': _service(flatId),
          });
        }
        if (options.method == 'GET' &&
            options.path.endsWith('/billing/additional-services')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'items': [_service(flatId)],
              'pagination': {
                'page': 1,
                'limit': 50,
                'total': 1,
                'totalPages': 1,
              },
            },
          });
        }
        return notFound(options.path);
      });
      final repo = BillingRepository(_api(adapter).billing);
      final created = await repo.createAdditionalService(
        CreateAdditionalServiceRequest(
          flatId: flatId,
          name: 'Additional car parking',
          monthlyChargePaise: 50000,
          quantity: 1,
          effectiveFrom: '2026-04-01T00:00:00.000Z',
        ),
      );
      expect(created.monthlyTotalPaise, 50000);
      final list = await repo.listAdditionalServices(force: true);
      expect(list.items, hasLength(1));
    });

    test('eligible flats list has no SQLite fallback on failure', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(500, {
          'success': false,
          'error': {'code': 'INTERNAL_ERROR', 'message': 'boom'},
        });
      });
      final repo = BillingRepository(_api(adapter).billing);
      await expectLater(repo.eligibleFlats(), throwsA(isA<ApiException>()));
      expect(repo.lastEligibleFlats, isNull);
    });

    test('adjust and cancel invalidate caches', () async {
      var mode = 'list';
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/adjust')) {
          mode = 'adjusted';
          return jsonBody(200, {
            'success': true,
            'data': _bill(billId, flatId, total: 410000),
          });
        }
        if (options.path.endsWith('/cancel')) {
          return jsonBody(200, {
            'success': true,
            'data': _bill(billId, flatId, status: 'CANCELLED'),
          });
        }
        if (options.path.endsWith('/billing/bills') && options.method == 'GET') {
          return jsonBody(200, {
            'success': true,
            'data': {
              'items': [_bill(billId, flatId)],
              'pagination': {
                'page': 1,
                'limit': 20,
                'total': 1,
                'totalPages': 1,
              },
            },
          });
        }
        return notFound(options.path);
      });
      final repo = BillingRepository(_api(adapter).billing);
      await repo.listAdminBills();
      expect(repo.lastAdminBills, isNotNull);
      await repo.adjustBill(billId, adjustmentsPaise: 10000);
      expect(mode, 'adjusted');
      expect(repo.lastAdminBills, isNull);
      await repo.cancelBill(billId, reason: 'Duplicate');
    });

    test('offline settlement and duplicate lock', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/payments/offline'), isTrue);
        return jsonBody(201, {
          'success': true,
          'data': {
            'paymentId': '507f1f77bcf86cd799439051',
            'alreadySettled': false,
            'receiptId': '507f1f77bcf86cd799439061',
            'billStatus': 'PAID',
            'outstandingPrincipalPaise': 0,
          },
        });
      });
      final repo = BillingRepository(_api(adapter).billing);
      final result = await repo.recordOfflinePayment(
        billId: billId,
        amountPaise: 400000,
        paidAt: '2026-04-11T10:00:00.000Z',
        referenceNumber: 'CHQ-1',
        idempotencyKey: 'k1',
      );
      expect(result.receiptId, isNotNull);
      expect(repo.paymentSubmitLocked, isFalse);
    });
  });

  group('Owner billing and payments', () {
    test('maps interest breakdown from server without local formula', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.contains('/interest'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'billId': billId,
            'principalOutstandingPaise': 400000,
            'overdueDays': 5,
            'annualInterestRateBps': 2400,
            'annualInterestRatePercent': 24,
            'accruedInterestPaise': 1315,
            'asOf': '2026-04-16T00:00:00.000Z',
            'dueDate': '2026-04-10T00:00:00.000Z',
            'dayCountConvention': 'actual/365',
            'rounding': 'floor_via_bigint_division',
            'principalEffectiveConvention': 'civil_midnight_of_settlement_date',
            'segments': [
              {
                'from': '2026-04-11T00:00:00.000Z',
                'to': '2026-04-16T00:00:00.000Z',
                'days': 5,
                'principalPaise': 400000,
                'interestPaise': 1315,
              },
            ],
          },
        });
      });
      final repo = BillingRepository(_api(adapter).billing);
      final interest = await repo.residentInterest(billId);
      expect(interest.accruedInterestPaise, 1315);
      expect(interest.annualInterestRatePercent, 24);
      expect(interest.segments, hasLength(1));
    });

    test('payment order and verify', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/payment-order')) {
          return jsonBody(201, {
            'success': true,
            'data': {
              'paymentId': '507f1f77bcf86cd799439051',
              'paymentNumber': 'PAY-1',
              'billId': billId,
              'amountPaise': 400000,
              'order': {
                'orderId': 'order_abc',
                'amountPaise': 400000,
                'currency': 'INR',
                'provider': 'razorpay',
                'keyId': 'rzp_test_x',
              },
            },
          });
        }
        if (options.path.endsWith('/verify-payment')) {
          expect(options.data['orderId'], 'order_abc');
          expect(options.data['paymentId'], 'pay_abc');
          expect(options.data['signature'], 'sig');
          return jsonBody(200, {
            'success': true,
            'data': {
              'paymentId': '507f1f77bcf86cd799439051',
              'alreadySettled': false,
              'receiptId': '507f1f77bcf86cd799439061',
              'billStatus': 'PAID',
              'outstandingPrincipalPaise': 0,
            },
          });
        }
        return notFound(options.path);
      });
      final repo = BillingRepository(_api(adapter).billing);
      final order = await repo.createPaymentOrder(billId);
      expect(order.order.keyId, 'rzp_test_x');
      final settlement = await repo.verifyPayment(
        orderId: 'order_abc',
        paymentId: 'pay_abc',
        signature: 'sig',
        billId: billId,
      );
      expect(settlement.receiptId, isNotNull);
    });

    test('tenant billing denial surfaces clearly', () {
      expect(
        ApiException(
          code: 'TENANT_BILLING_DENIED',
          message: 'Tenants cannot access billing APIs',
          statusCode: 403,
        ).code,
        'TENANT_BILLING_DENIED',
      );
    });

    test('failed payment order does not invent success', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {
            'code': 'PAYMENTS_LIVE_DISABLED',
            'message': 'Live payments disabled',
          },
        });
      });
      final repo = BillingRepository(_api(adapter).billing);
      await expectLater(
        repo.createPaymentOrder(billId),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'PAYMENTS_LIVE_DISABLED',
          ),
        ),
      );
    });

    test('cache invalidation after financial mutation', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/billing/bills')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'items': [_bill(billId, flatId)],
              'pagination': {
                'page': 1,
                'limit': 20,
                'total': 1,
                'totalPages': 1,
              },
            },
          });
        }
        return notFound(options.path);
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.billing.listResidentBills();
      expect(repos.billing.lastResidentBills, isNotNull);
      repos.invalidateAfterFinancialMutation(billId: billId);
      expect(repos.billing.lastResidentBills, isNull);
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

Map<String, Object?> _service(String flatId) => {
      'id': '507f1f77bcf86cd799439061',
      'societyId': societyId,
      'flatId': flatId,
      'name': 'Additional car parking',
      'monthlyChargePaise': 50000,
      'quantity': 1,
      'monthlyTotalPaise': 50000,
      'effectiveFrom': '2026-04-01T00:00:00.000Z',
      'isActive': true,
      'createdAt': '2026-04-01T00:00:00.000Z',
      'updatedAt': '2026-04-01T00:00:00.000Z',
      'flatNumber': 'A-101',
      'wingCode': 'A',
    };

Map<String, Object?> _bill(
  String id,
  String flatId, {
  String status = 'ISSUED',
  int total = 400000,
}) =>
    {
      'id': id,
      'billNumber': 'BILL-2026-000001',
      'flatId': flatId,
      'ownerUserId': '507f1f77bcf86cd799439021',
      'billingPeriodStart': '2026-04-01T00:00:00.000Z',
      'billingPeriodEnd': '2026-04-30T00:00:00.000Z',
      'numberOfMonths': 1,
      'monthlyRatePaise': 400000,
      'baseAmountPaise': 400000,
      'totalAmountPaise': total,
      'outstandingPrincipalPaise': 400000,
      'interestAccruedPaise': 1200,
      'amountPaidPaise': 0,
      'dueDate': '2026-04-10T00:00:00.000Z',
      'status': status,
      'flatNumberSnapshot': 'A-101',
      'wingCodeSnapshot': 'A',
      'flatTypeSnapshot': '2BHK',
      'ownerNameSnapshot': 'Owner',
      'ownerEmailSnapshot': 'owner@example.com',
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
