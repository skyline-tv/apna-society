import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/models/collection_models.dart';
import 'package:apna_society/api/repositories/collection_repository.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const societyId = '507f1f77bcf86cd799439011';
  const collectionId = '507f1f77bcf86cd799439081';
  const chargeId = '507f1f77bcf86cd799439082';
  const flatId = '507f1f77bcf86cd799439013';

  tearDown(clearLiveRepositories);

  group('Collection models', () {
    test('parse admin collection, dashboard and resident charge', () {
      final collection = CollectionSummary.fromJson(_collection(collectionId));
      expect(collection.collectionNumber, 'COL-2026-000001');
      expect(collection.outstandingPaise, 80000);
      expect(collection.allowPartialPayment, isFalse);

      final dashboard = CollectionDashboard.fromJson(_dashboard());
      expect(dashboard.assignedFlatCount, 140);
      expect(dashboard.paidFlats, 10);
      expect(dashboard.collectionPercentage, 12.5);

      final charge = CollectionCharge.fromJson(_charge(chargeId, collectionId, flatId));
      expect(charge.flatLabel, 'A-101');
      expect(charge.outstandingPaise, 10000);
      expect(charge.collectionTitle, 'Diwali celebration');
    });
  });

  group('Collection repository', () {
    test('previews and creates a collection', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/collections/preview') &&
            options.method == 'POST') {
          return jsonBody(200, {
            'success': true,
            'data': {
              'assignedFlatCount': 140,
              'amountMode': 'PER_FLAT',
              'assignmentType': 'ALL_FLATS',
              'defaultAmountPaise': 10000,
              'expectedTotalPaise': 1400000,
              'allocations': [
                {
                  'flatId': flatId,
                  'flatLabel': 'A-101',
                  'amountPaise': 10000,
                  'occupancyStatus': 'VACANT',
                  'ownerName': 'Unassigned',
                  'wingCode': 'A',
                },
              ],
            },
          });
        }
        if (options.path.endsWith('/collections') && options.method == 'POST') {
          return jsonBody(201, {
            'success': true,
            'data': _collection(collectionId),
          });
        }
        return notFound(options.path);
      });
      final repo = CollectionRepository(_api(adapter, societyId).collections);
      final preview = await repo.preview(
        const CreateCollectionRequest(
          title: 'Diwali celebration collection',
          description: 'Festival lighting',
          amountMode: 'PER_FLAT',
          assignmentType: 'ALL_FLATS',
          amountPaise: 10000,
          dueDate: '2026-12-31T00:00:00.000+05:30',
          allowPartialPayment: false,
        ),
      );
      expect(preview.assignedFlatCount, 140);
      expect(preview.expectedTotalPaise, 1400000);
      final created = await repo.create(
        const CreateCollectionRequest(
          title: 'Diwali celebration collection',
          description: 'Festival lighting',
          amountMode: 'PER_FLAT',
          assignmentType: 'ALL_FLATS',
          amountPaise: 10000,
          dueDate: '2026-12-31T00:00:00.000+05:30',
          allowPartialPayment: false,
        ),
      );
      expect(created.id, collectionId);
      expect(created.assignedFlatCount, 140);
    });

    test('lists resident charges and payment order', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/resident/collections') &&
            options.method == 'GET') {
          return jsonBody(200, {
            'success': true,
            'data': {
              'items': [_charge(chargeId, collectionId, flatId)],
            },
          });
        }
        if (options.path.contains('/payment-order')) {
          return jsonBody(201, {
            'success': true,
            'data': {
              'paymentId': '507f1f77bcf86cd799439091',
              'paymentNumber': 'COLPAY-2026-000001',
              'chargeId': chargeId,
              'collectionId': collectionId,
              'amountPaise': 10000,
              'order': {
                'orderId': 'order_demo_1',
                'amountPaise': 10000,
                'currency': 'INR',
                'provider': 'razorpay-mock',
                'keyId': 'rzp_test',
              },
            },
          });
        }
        return notFound(options.path);
      });
      final repo = CollectionRepository(_api(adapter, societyId).collections);
      final items = await repo.listResident();
      expect(items, hasLength(1));
      expect(items.first.collectionTitle, 'Diwali celebration');
      final order = await repo.createPaymentOrder(chargeId);
      expect(order.order.provider, 'razorpay-mock');
      expect(order.amountPaise, 10000);
    });
  });
}

ApnaApi _api(ScriptedAdapter adapter, String societyId) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4000'));
  dio.httpClientAdapter = adapter;
  final client = ApiClient(
    config: ApiConfig.resolve(flavorName: 'development'),
    dio: dio,
  );
  client.societyId = societyId;
  return ApnaApi(client: client);
}

Map<String, Object?> _collection(String id) => {
      'id': id,
      'collectionNumber': 'COL-2026-000001',
      'title': 'Diwali celebration',
      'description': 'Festival lighting',
      'amountMode': 'PER_FLAT',
      'assignmentType': 'ALL_FLATS',
      'amountPaise': 10000,
      'allowPartialPayment': false,
      'dueDate': '2026-12-31T00:00:00.000Z',
      'status': 'ACTIVE',
      'expectedTotalPaise': 1400000,
      'collectedPaise': 1320000,
      'outstandingPaise': 80000,
      'assignedFlatCount': 140,
      'collectionPercentage': 94.28,
      'createdAt': '2026-10-01T00:00:00.000Z',
      'updatedAt': '2026-10-01T00:00:00.000Z',
    };

Map<String, Object?> _dashboard() => {
      'assignedFlatCount': 140,
      'expectedTotalPaise': 1400000,
      'collectedPaise': 175000,
      'outstandingPaise': 1225000,
      'paidFlats': 10,
      'partiallyPaidFlats': 5,
      'pendingFlats': 125,
      'overdueFlats': 2,
      'collectionPercentage': 12.5,
    };

Map<String, Object?> _charge(String id, String collectionId, String flatId) => {
      'id': id,
      'collectionId': collectionId,
      'flatId': flatId,
      'amountPaise': 10000,
      'adjustmentsPaise': 0,
      'assignedAmountPaise': 10000,
      'amountPaidPaise': 0,
      'outstandingPaise': 10000,
      'status': 'PENDING',
      'paymentStatus': 'PENDING',
      'overdue': false,
      'dueDate': '2026-12-31T00:00:00.000Z',
      'wingCodeSnapshot': 'A',
      'flatNumberSnapshot': '101',
      'occupancyStatusSnapshot': 'VACANT',
      'ownerNameSnapshot': 'Unassigned',
      'collectionTitle': 'Diwali celebration',
      'collectionNumber': 'COL-2026-000001',
      'collectionStatus': 'ACTIVE',
      'allowPartialPayment': false,
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
