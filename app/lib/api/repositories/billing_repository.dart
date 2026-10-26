import '../models/billing_models.dart';
import '../models/common.dart';
import '../services/billing_api.dart';

/// Cached admin/resident billing reads and financial mutations.
class BillingRepository {
  BillingRepository(this._api);

  final BillingApi _api;

  Paged<Bill>? lastAdminBills;
  String? lastAdminBillsKey;
  Paged<Bill>? lastResidentBills;
  String? lastResidentBillsKey;
  Paged<PaymentSummary>? lastAdminPayments;
  Paged<PaymentSummary>? lastResidentPayments;
  BillingSummary? lastSummary;
  List<EligibleFlat>? lastEligibleFlats;
  Paged<AdditionalService>? lastAdditionalServices;
  final Map<String, Bill> _bills = {};
  final Map<String, AdditionalService> _services = {};
  final Map<String, InterestBreakdown> _interest = {};
  final Map<String, ReceiptDetail> _receipts = {};

  /// Prevents duplicate payment-order / verify / offline submissions.
  bool paymentSubmitLocked = false;

  void clear() {
    lastAdminBills = null;
    lastAdminBillsKey = null;
    lastResidentBills = null;
    lastResidentBillsKey = null;
    lastAdminPayments = null;
    lastResidentPayments = null;
    lastSummary = null;
    lastEligibleFlats = null;
    lastAdditionalServices = null;
    _bills.clear();
    _services.clear();
    _interest.clear();
    _receipts.clear();
    paymentSubmitLocked = false;
  }

  void invalidateFinancialCaches({String? billId}) {
    lastAdminBills = null;
    lastAdminBillsKey = null;
    lastResidentBills = null;
    lastResidentBillsKey = null;
    lastAdminPayments = null;
    lastResidentPayments = null;
    lastSummary = null;
    lastEligibleFlats = null;
    lastAdditionalServices = null;
    _services.clear();
    if (billId != null) {
      _bills.remove(billId);
      _interest.remove(billId);
    } else {
      _bills.clear();
      _interest.clear();
    }
    _receipts.clear();
  }

  Future<Paged<Bill>> listAdminBills({
    ListBillsQuery query = const ListBillsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastAdminBills != null && lastAdminBillsKey == key) {
      return lastAdminBills!;
    }
    final page = await _api.listAdminBills(query: query);
    lastAdminBills = page;
    lastAdminBillsKey = key;
    for (final bill in page.items) {
      _bills[bill.id] = bill;
    }
    return page;
  }

  Future<Paged<Bill>> listResidentBills({
    ListBillsQuery query = const ListBillsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastResidentBills != null && lastResidentBillsKey == key) {
      return lastResidentBills!;
    }
    final page = await _api.listResidentBills(query: query);
    lastResidentBills = page;
    lastResidentBillsKey = key;
    for (final bill in page.items) {
      _bills[bill.id] = bill;
    }
    return page;
  }

  Future<Bill> adminBill(String billId, {bool force = false}) async {
    if (!force && _bills.containsKey(billId)) return _bills[billId]!;
    final bill = await _api.adminBill(billId);
    _bills[billId] = bill;
    return bill;
  }

  Future<Bill> residentBill(String billId, {bool force = false}) async {
    if (!force && _bills.containsKey(billId)) return _bills[billId]!;
    final bill = await _api.residentBill(billId);
    _bills[billId] = bill;
    return bill;
  }

  Future<InterestBreakdown> adminInterest(String billId, {bool force = false}) async {
    if (!force && _interest.containsKey(billId)) return _interest[billId]!;
    final interest = await _api.adminBillInterest(billId);
    _interest[billId] = interest;
    return interest;
  }

  Future<InterestBreakdown> residentInterest(String billId, {bool force = false}) async {
    if (!force && _interest.containsKey(billId)) return _interest[billId]!;
    final interest = await _api.residentBillInterest(billId);
    _interest[billId] = interest;
    return interest;
  }

  Future<BillingSummary> summary({
    String? billingPeriodStart,
    String? wingCode,
    bool force = false,
  }) async {
    if (!force &&
        lastSummary != null &&
        billingPeriodStart == null &&
        wingCode == null) {
      return lastSummary!;
    }
    final summary = await _api.summary(
      billingPeriodStart: billingPeriodStart,
      wingCode: wingCode,
    );
    lastSummary = summary;
    return summary;
  }

  Future<List<EligibleFlat>> eligibleFlats({bool force = false}) async {
    if (!force && lastEligibleFlats != null) return lastEligibleFlats!;
    final flats = await _api.eligibleFlats();
    lastEligibleFlats = flats;
    return flats;
  }

  Future<GenerateBillsResult> generateBills({
    required String billingPeriodStart,
    required int numberOfMonths,
    String? dueDate,
    String? notes,
  }) async {
    final result = await _api.generateBills(
      billingPeriodStart: billingPeriodStart,
      numberOfMonths: numberOfMonths,
      dueDate: dueDate,
      notes: notes,
    );
    invalidateFinancialCaches();
    return result;
  }

  Future<Bill> adjustBill(
    String billId, {
    required int adjustmentsPaise,
    String? notes,
  }) async {
    final bill = await _api.adjustBill(
      billId,
      adjustmentsPaise: adjustmentsPaise,
      notes: notes,
    );
    invalidateFinancialCaches(billId: billId);
    _bills[billId] = bill;
    return bill;
  }

  Future<Bill> cancelBill(String billId, {required String reason}) async {
    final bill = await _api.cancelBill(billId, reason: reason);
    invalidateFinancialCaches(billId: billId);
    _bills[billId] = bill;
    return bill;
  }

  Future<PaymentSettlement> recordOfflinePayment({
    required String billId,
    required int amountPaise,
    required String paidAt,
    String? referenceNumber,
    String? paymentMethod,
    String? notes,
    String? idempotencyKey,
  }) async {
    if (paymentSubmitLocked) {
      throw StateError('A payment submission is already in progress.');
    }
    paymentSubmitLocked = true;
    try {
      final result = await _api.recordOfflinePayment(
        billId: billId,
        amountPaise: amountPaise,
        paidAt: paidAt,
        paymentMethod: paymentMethod,
        referenceNumber: referenceNumber,
        notes: notes,
        idempotencyKey: idempotencyKey,
      );
      invalidateFinancialCaches(billId: billId);
      return result;
    } finally {
      paymentSubmitLocked = false;
    }
  }

  Future<CreatePaymentOrderResult> createPaymentOrder(String billId) async {
    if (paymentSubmitLocked) {
      throw StateError('A payment submission is already in progress.');
    }
    paymentSubmitLocked = true;
    try {
      return await _api.createPaymentOrder(billId);
    } finally {
      paymentSubmitLocked = false;
    }
  }

  Future<PaymentSettlement> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
    String? billId,
  }) async {
    if (paymentSubmitLocked) {
      throw StateError('A payment submission is already in progress.');
    }
    paymentSubmitLocked = true;
    try {
      final result = await _api.verifyPayment(
        orderId: orderId,
        paymentId: paymentId,
        signature: signature,
      );
      invalidateFinancialCaches(billId: billId);
      return result;
    } finally {
      paymentSubmitLocked = false;
    }
  }

  /// Completes a mock/demo checkout on the server (no client HMAC).
  Future<PaymentSettlement> completeDemoPayment({
    required String orderId,
    required String outcome,
    String? billId,
  }) async {
    if (paymentSubmitLocked) {
      throw StateError('A payment submission is already in progress.');
    }
    paymentSubmitLocked = true;
    try {
      final result = await _api.completeDemoPayment(
        orderId: orderId,
        outcome: outcome,
      );
      invalidateFinancialCaches(billId: billId);
      return result;
    } finally {
      paymentSubmitLocked = false;
    }
  }

  Future<Paged<PaymentSummary>> listAdminPayments({
    String? status,
    String? billId,
    int? page,
    int? limit,
    bool force = false,
  }) async {
    if (!force && lastAdminPayments != null && billId == null && status == null) {
      return lastAdminPayments!;
    }
    final result = await _api.listAdminPayments(
      status: status,
      billId: billId,
      page: page,
      limit: limit,
    );
    if (billId == null && status == null) lastAdminPayments = result;
    return result;
  }

  Future<Paged<PaymentSummary>> listResidentPayments({
    String? status,
    String? billId,
    int? page,
    int? limit,
    bool force = false,
  }) async {
    if (!force &&
        lastResidentPayments != null &&
        billId == null &&
        status == null) {
      return lastResidentPayments!;
    }
    final result = await _api.listResidentPayments(
      status: status,
      billId: billId,
      page: page,
      limit: limit,
    );
    if (billId == null && status == null) lastResidentPayments = result;
    return result;
  }

  Future<PaymentSummary> refundPayment(
    String paymentId, {
    required String reason,
  }) async {
    final payment = await _api.refundPayment(paymentId, reason: reason);
    invalidateFinancialCaches(billId: payment.billId);
    return payment;
  }

  Future<ReceiptDetail> adminReceipt(String receiptId, {bool force = false}) async {
    if (!force && _receipts.containsKey(receiptId)) return _receipts[receiptId]!;
    final receipt = await _api.adminReceipt(receiptId);
    _receipts[receiptId] = receipt;
    return receipt;
  }

  Future<ReceiptDetail> residentReceipt(String receiptId, {bool force = false}) async {
    if (!force && _receipts.containsKey(receiptId)) return _receipts[receiptId]!;
    final receipt = await _api.residentReceipt(receiptId);
    _receipts[receiptId] = receipt;
    return receipt;
  }

  Future<ReceiptDetail> paymentReceipt(
    String paymentId, {
    required bool resident,
    bool force = false,
  }) async {
    final cacheKey = 'payment:$paymentId';
    if (!force && _receipts.containsKey(cacheKey)) return _receipts[cacheKey]!;
    final receipt = resident
        ? await _api.residentPaymentReceipt(paymentId)
        : await _api.adminPaymentReceipt(paymentId);
    _receipts[cacheKey] = receipt;
    _receipts[receipt.receipt.id] = receipt;
    return receipt;
  }

  Future<Paged<ReceiptSummary>> listResidentReceipts({
    int? page,
    int? limit,
  }) {
    return _api.listResidentReceipts(page: page, limit: limit);
  }

  Future<Paged<ReceiptSummary>> listAdminReceipts({
    int? page,
    int? limit,
  }) {
    return _api.listAdminReceipts(page: page, limit: limit);
  }

  Future<Paged<AdditionalService>> listAdditionalServices({
    String? flatId,
    String? wingId,
    bool? isActive,
    int? page,
    int? limit,
    bool force = false,
  }) async {
    if (!force &&
        lastAdditionalServices != null &&
        flatId == null &&
        wingId == null &&
        isActive == null) {
      return lastAdditionalServices!;
    }
    final result = await _api.listAdditionalServices(
      flatId: flatId,
      wingId: wingId,
      isActive: isActive,
      page: page,
      limit: limit,
    );
    if (flatId == null && wingId == null && isActive == null) {
      lastAdditionalServices = result;
    }
    for (final service in result.items) {
      _services[service.id] = service;
    }
    return result;
  }

  Future<AdditionalService> createAdditionalService(
    CreateAdditionalServiceRequest request,
  ) async {
    final service = await _api.createAdditionalService(request);
    lastAdditionalServices = null;
    lastEligibleFlats = null;
    _services[service.id] = service;
    return service;
  }

  Future<AdditionalService> updateAdditionalService(
    String serviceId,
    UpdateAdditionalServiceRequest request,
  ) async {
    final service = await _api.updateAdditionalService(serviceId, request);
    lastAdditionalServices = null;
    lastEligibleFlats = null;
    _services[service.id] = service;
    return service;
  }

  Future<AdditionalService> deactivateAdditionalService(
    String serviceId, {
    String? reason,
  }) async {
    final service = await _api.deactivateAdditionalService(
      serviceId,
      reason: reason,
    );
    lastAdditionalServices = null;
    lastEligibleFlats = null;
    _services[service.id] = service;
    return service;
  }
}
