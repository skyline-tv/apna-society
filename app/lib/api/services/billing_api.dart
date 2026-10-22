import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/api_exception.dart';
import '../http/json_read.dart';
import '../models/billing_models.dart';
import '../models/common.dart';

/// Admin and resident billing routes. Amounts stay in integer paise.
class BillingApi {
  BillingApi(this._client);
  final ApiClient _client;

  static const _admin = '${ApiConfig.apiPrefix}/admin';
  static const _resident = '${ApiConfig.apiPrefix}/resident';

  Future<GenerateBillsResult> generateBills({
    required String billingPeriodStart,
    required int numberOfMonths,
    String? notes,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/billing/generate',
      body: omitNulls({
        'billingPeriodStart': billingPeriodStart,
        'numberOfMonths': numberOfMonths,
        'notes': notes,
      }),
      societyId: societyId,
      decode: GenerateBillsResult.fromJson,
    );
  }

  Future<Paged<Bill>> listAdminBills({
    ListBillsQuery query = const ListBillsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/billing/bills',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Bill.fromJson),
    );
  }

  Future<Bill> adminBill(String billId, {String? societyId}) {
    return _client.get(
      '$_admin/billing/bills/$billId',
      societyId: societyId,
      decode: Bill.fromJson,
    );
  }

  Future<InterestBreakdown> adminBillInterest(
    String billId, {
    String? asOf,
    String? societyId,
  }) {
    return _client.get(
      '$_admin/billing/bills/$billId/interest',
      query: omitNulls({'asOf': asOf}),
      societyId: societyId,
      decode: InterestBreakdown.fromJson,
    );
  }

  Future<BillingSummary> summary({
    String? billingPeriodStart,
    String? wingCode,
    String? societyId,
  }) {
    return _client.get(
      '$_admin/billing/summary',
      query: omitNulls({
        'billingPeriodStart': billingPeriodStart,
        'wingCode': wingCode,
      }),
      societyId: societyId,
      decode: BillingSummary.fromJson,
    );
  }

  Future<List<EligibleFlat>> eligibleFlats({String? societyId}) {
    return _client.get(
      '$_admin/billing/eligible-flats',
      societyId: societyId,
      decode: (data) {
        if (data is! List) {
          throw ApiParseException('Expected eligible flat list');
        }
        return data
            .map((item) => EligibleFlat.fromJson(requireMap(item, 'flat')))
            .toList();
      },
    );
  }

  Future<Bill> adjustBill(
    String billId, {
    required int adjustmentsPaise,
    String? notes,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/billing/bills/$billId/adjust',
      societyId: societyId,
      body: omitNulls({
        'adjustmentsPaise': adjustmentsPaise,
        'notes': notes,
      }),
      decode: Bill.fromJson,
    );
  }

  Future<Bill> cancelBill(
    String billId, {
    required String reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/billing/bills/$billId/cancel',
      societyId: societyId,
      body: {'reason': reason.trim()},
      decode: Bill.fromJson,
    );
  }

  Future<InterestRefreshResult> refreshInterest({String? societyId}) {
    return _client.post(
      '$_admin/billing/interest/refresh',
      societyId: societyId,
      decode: InterestRefreshResult.fromJson,
    );
  }

  Future<PaymentSummary> refundPayment(
    String paymentId, {
    required String reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/payments/$paymentId/refund',
      societyId: societyId,
      body: {'reason': reason.trim()},
      decode: (data) => PaymentSummary.fromJson(requireMap(data, 'payment')),
    );
  }

  Future<PaymentSettlement> recordOfflinePayment({
    required String billId,
    required int amountPaise,
    required String paidAt,
    required String referenceNumber,
    String? notes,
    String? idempotencyKey,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/payments/offline',
      body: omitNulls({
        'billId': billId,
        'amountPaise': amountPaise,
        'paidAt': paidAt,
        'referenceNumber': referenceNumber,
        'notes': notes,
        'idempotencyKey': idempotencyKey,
      }),
      societyId: societyId,
      decode: PaymentSettlement.fromJson,
    );
  }

  Future<Paged<PaymentSummary>> listAdminPayments({
    String? status,
    String? billId,
    int? page,
    int? limit,
    String? societyId,
  }) {
    return _client.get(
      '$_admin/payments',
      query: omitNulls({
        'status': status,
        'billId': billId,
        'page': page,
        'limit': limit,
      }),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, PaymentSummary.fromJson),
    );
  }

  Future<PaymentSummary> adminPayment(String paymentId, {String? societyId}) {
    return _client.get(
      '$_admin/payments/$paymentId',
      societyId: societyId,
      decode: (data) => PaymentSummary.fromJson(requireMap(data, 'payment')),
    );
  }

  Future<Paged<ReceiptSummary>> listAdminReceipts({
    int? page,
    int? limit,
    String? societyId,
  }) {
    return _client.get(
      '$_admin/receipts',
      query: omitNulls({'page': page, 'limit': limit}),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, ReceiptSummary.fromJson),
    );
  }

  Future<ReceiptDetail> adminReceipt(String receiptId, {String? societyId}) {
    return _client.get(
      '$_admin/receipts/$receiptId',
      societyId: societyId,
      decode: ReceiptDetail.fromJson,
    );
  }

  Future<Paged<Bill>> listResidentBills({
    ListBillsQuery query = const ListBillsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_resident/billing/bills',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Bill.fromJson),
    );
  }

  Future<Bill> residentBill(String billId, {String? societyId}) {
    return _client.get(
      '$_resident/billing/bills/$billId',
      societyId: societyId,
      decode: Bill.fromJson,
    );
  }

  Future<InterestBreakdown> residentBillInterest(
    String billId, {
    String? asOf,
    String? societyId,
  }) {
    return _client.get(
      '$_resident/billing/bills/$billId/interest',
      query: omitNulls({'asOf': asOf}),
      societyId: societyId,
      decode: InterestBreakdown.fromJson,
    );
  }

  Future<CreatePaymentOrderResult> createPaymentOrder(
    String billId, {
    String? societyId,
  }) {
    return _client.post(
      '$_resident/billing/bills/$billId/payment-order',
      societyId: societyId,
      decode: CreatePaymentOrderResult.fromJson,
    );
  }

  Future<PaymentSettlement> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
    String? societyId,
  }) {
    return _client.post(
      '$_resident/billing/verify-payment',
      body: {
        'orderId': orderId,
        'paymentId': paymentId,
        'signature': signature,
      },
      societyId: societyId,
      decode: PaymentSettlement.fromJson,
    );
  }

  /// Server-side mock settlement. Clients must never supply an HMAC secret.
  Future<PaymentSettlement> completeDemoPayment({
    required String orderId,
    required String outcome,
    String? societyId,
  }) {
    return _client.post(
      '$_resident/billing/demo-complete',
      body: {
        'orderId': orderId,
        'outcome': outcome,
      },
      societyId: societyId,
      decode: PaymentSettlement.fromJson,
    );
  }

  Future<Paged<PaymentSummary>> listResidentPayments({
    String? status,
    String? billId,
    int? page,
    int? limit,
    String? societyId,
  }) {
    return _client.get(
      '$_resident/billing/payments',
      query: omitNulls({
        'status': status,
        'billId': billId,
        'page': page,
        'limit': limit,
      }),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, PaymentSummary.fromJson),
    );
  }

  Future<Paged<ReceiptSummary>> listResidentReceipts({
    int? page,
    int? limit,
    String? societyId,
  }) {
    return _client.get(
      '$_resident/billing/receipts',
      query: omitNulls({'page': page, 'limit': limit}),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, ReceiptSummary.fromJson),
    );
  }

  Future<ReceiptDetail> residentReceipt(String receiptId, {String? societyId}) {
    return _client.get(
      '$_resident/billing/receipts/$receiptId',
      societyId: societyId,
      decode: ReceiptDetail.fromJson,
    );
  }

  Future<AdditionalService> createAdditionalService(
    CreateAdditionalServiceRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_admin/billing/additional-services',
      body: request.toJson(),
      societyId: societyId,
      decode: AdditionalService.fromJson,
    );
  }

  Future<Paged<AdditionalService>> listAdditionalServices({
    String? flatId,
    String? wingId,
    bool? isActive,
    int? page,
    int? limit,
    String? societyId,
  }) {
    return _client.get(
      '$_admin/billing/additional-services',
      query: omitNulls({
        'flatId': flatId,
        'wingId': wingId,
        'isActive': isActive,
        'page': page,
        'limit': limit,
      }),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, AdditionalService.fromJson),
    );
  }

  Future<AdditionalService> additionalService(
    String serviceId, {
    String? societyId,
  }) {
    return _client.get(
      '$_admin/billing/additional-services/$serviceId',
      societyId: societyId,
      decode: AdditionalService.fromJson,
    );
  }

  Future<AdditionalService> updateAdditionalService(
    String serviceId,
    UpdateAdditionalServiceRequest request, {
    String? societyId,
  }) {
    return _client.patch(
      '$_admin/billing/additional-services/$serviceId',
      body: request.toJson(),
      societyId: societyId,
      decode: AdditionalService.fromJson,
    );
  }

  Future<AdditionalService> deactivateAdditionalService(
    String serviceId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/billing/additional-services/$serviceId/deactivate',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: AdditionalService.fromJson,
    );
  }
}
