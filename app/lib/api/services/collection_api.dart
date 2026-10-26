import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/json_read.dart';
import '../models/billing_models.dart' show PaymentSettlement;
import '../models/collection_models.dart';
import '../models/common.dart';

class CollectionApi {
  CollectionApi(this._client);
  final ApiClient _client;

  static const _admin = '${ApiConfig.apiPrefix}/admin';
  static const _resident = '${ApiConfig.apiPrefix}/resident';

  Future<CollectionPreview> preview(CreateCollectionRequest request) {
    return _client.post(
      '$_admin/collections/preview',
      body: request.toJson(),
      decode: CollectionPreview.fromJson,
    );
  }

  Future<CollectionSummary> create(CreateCollectionRequest request) {
    return _client.post(
      '$_admin/collections',
      body: request.toJson(),
      decode: CollectionSummary.fromJson,
    );
  }

  Future<Paged<CollectionSummary>> listAdmin({
    String? status,
    String? search,
    int? page,
    int? limit,
  }) {
    return _client.get(
      '$_admin/collections',
      query: omitNulls({
        'status': status,
        'search': search,
        'page': page,
        'limit': limit,
      }),
      decode: (data) => Paged.fromJson(data, CollectionSummary.fromJson),
    );
  }

  Future<CollectionSummary> adminCollection(String collectionId) {
    return _client.get(
      '$_admin/collections/$collectionId',
      decode: CollectionSummary.fromJson,
    );
  }

  Future<CollectionSummary> update(
    String collectionId, {
    String? title,
    String? description,
    String? dueDate,
    String? paymentInstructions,
    bool? allowPartialPayment,
  }) {
    return _client.patch(
      '$_admin/collections/$collectionId',
      body: omitNulls({
        'title': title,
        'description': description,
        'dueDate': dueDate,
        'paymentInstructions': paymentInstructions,
        'allowPartialPayment': allowPartialPayment,
      }),
      decode: CollectionSummary.fromJson,
    );
  }

  Future<CollectionPreview> previewAddFlats(
    String collectionId,
    AddCollectionFlatsRequest request,
  ) {
    return _client.post(
      '$_admin/collections/$collectionId/flats/preview',
      body: request.toJson(),
      decode: CollectionPreview.fromJson,
    );
  }

  Future<CollectionSummary> addFlats(
    String collectionId,
    AddCollectionFlatsRequest request,
  ) {
    return _client.post(
      '$_admin/collections/$collectionId/flats',
      body: request.toJson(),
      decode: CollectionSummary.fromJson,
    );
  }

  Future<CollectionSummary> removeFlats(
    String collectionId,
    RemoveCollectionFlatsRequest request,
  ) {
    return _client.post(
      '$_admin/collections/$collectionId/flats/remove',
      body: request.toJson(),
      decode: CollectionSummary.fromJson,
    );
  }

  Future<CollectionSummary> close(String collectionId) {
    return _client.post(
      '$_admin/collections/$collectionId/close',
      decode: CollectionSummary.fromJson,
    );
  }

  Future<CollectionSummary> cancel(String collectionId, {required String reason}) {
    return _client.post(
      '$_admin/collections/$collectionId/cancel',
      body: {'reason': reason},
      decode: CollectionSummary.fromJson,
    );
  }

  Future<CollectionDashboard> dashboard(String collectionId) {
    return _client.get(
      '$_admin/collections/$collectionId/dashboard',
      decode: CollectionDashboard.fromJson,
    );
  }

  Future<Paged<CollectionCharge>> listCharges(
    String collectionId, {
    CollectionChargeQuery query = const CollectionChargeQuery(),
  }) {
    return _client.get(
      '$_admin/collections/$collectionId/charges',
      query: query.toQuery(),
      decode: (data) => Paged.fromJson(data, CollectionCharge.fromJson),
    );
  }

  Future<List<int>> exportChargesCsv(String collectionId) {
    return _client.getBytes('$_admin/collections/$collectionId/charges.csv');
  }

  Future<Paged<CollectionPayment>> listAdminPayments(
    String collectionId, {
    String? status,
    String? chargeId,
    int? page,
    int? limit,
  }) {
    return _client.get(
      '$_admin/collections/$collectionId/payments',
      query: omitNulls({
        'status': status,
        'chargeId': chargeId,
        'page': page,
        'limit': limit,
      }),
      decode: (data) => Paged.fromJson(data, CollectionPayment.fromJson),
    );
  }

  Future<CollectionCharge> adjustCharge(
    String chargeId, {
    required int deltaPaise,
    required String reason,
  }) {
    return _client.post(
      '$_admin/collections/charges/$chargeId/adjust',
      body: {'deltaPaise': deltaPaise, 'reason': reason},
      decode: CollectionCharge.fromJson,
    );
  }

  Future<PaymentSettlement> recordOffline({
    required String chargeId,
    required int amountPaise,
    required String paidAt,
    required String referenceNumber,
    String? paymentMethod,
    String? notes,
    String? idempotencyKey,
  }) {
    return _client.post(
      '$_admin/collections/payments/offline',
      body: omitNulls({
        'chargeId': chargeId,
        'amountPaise': amountPaise,
        'paidAt': paidAt,
        'paymentMethod': paymentMethod,
        'referenceNumber': referenceNumber,
        'notes': notes,
        'idempotencyKey': idempotencyKey,
      }),
      decode: PaymentSettlement.fromJson,
    );
  }

  Future<CollectionReceiptDetail> adminReceipt(String receiptId) {
    return _client.get(
      '$_admin/collections/receipts/$receiptId',
      decode: CollectionReceiptDetail.fromJson,
    );
  }

  Future<CollectionReceiptDetail> adminPaymentReceipt(String paymentId) {
    return _client.get(
      '$_admin/collections/payments/$paymentId/receipt',
      decode: CollectionReceiptDetail.fromJson,
    );
  }

  Future<List<CollectionCharge>> listResident() {
    return _client.get(
      '$_resident/collections',
      decode: (data) {
        final json = requireMap(data, 'resident collections');
        return requireMapList(json, 'items').map(CollectionCharge.fromJson).toList();
      },
    );
  }

  Future<CollectionCharge> residentCharge(String chargeId) {
    return _client.get(
      '$_resident/collections/charges/$chargeId',
      decode: CollectionCharge.fromJson,
    );
  }

  Future<CollectionPaymentOrderResult> createPaymentOrder(
    String chargeId, {
    int? amountPaise,
  }) {
    return _client.post(
      '$_resident/collections/charges/$chargeId/payment-order',
      body: omitNulls({'amountPaise': amountPaise}),
      decode: CollectionPaymentOrderResult.fromJson,
    );
  }

  Future<PaymentSettlement> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) {
    return _client.post(
      '$_resident/collections/verify-payment',
      body: {
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
      },
      decode: PaymentSettlement.fromJson,
    );
  }

  Future<PaymentSettlement> completeDemoPayment({
    required String orderId,
    required String outcome,
  }) {
    return _client.post(
      '$_resident/collections/demo-complete',
      body: {'orderId': orderId, 'outcome': outcome},
      decode: PaymentSettlement.fromJson,
    );
  }

  Future<Paged<CollectionPayment>> listResidentPayments({
    String? chargeId,
    String? status,
    int? page,
    int? limit,
  }) {
    return _client.get(
      '$_resident/collections/payments',
      query: omitNulls({
        'chargeId': chargeId,
        'status': status,
        'page': page,
        'limit': limit,
      }),
      decode: (data) => Paged.fromJson(data, CollectionPayment.fromJson),
    );
  }

  Future<CollectionReceiptDetail> residentReceipt(String receiptId) {
    return _client.get(
      '$_resident/collections/receipts/$receiptId',
      decode: CollectionReceiptDetail.fromJson,
    );
  }

  Future<CollectionReceiptDetail> residentPaymentReceipt(String paymentId) {
    return _client.get(
      '$_resident/collections/payments/$paymentId/receipt',
      decode: CollectionReceiptDetail.fromJson,
    );
  }
}
