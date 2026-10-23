import '../models/billing_models.dart' show PaymentSettlement;
import '../models/collection_models.dart';
import '../models/common.dart';
import '../services/collection_api.dart';

class CollectionRepository {
  CollectionRepository(this._api);
  final CollectionApi _api;

  Paged<CollectionSummary>? lastAdminCollections;
  List<CollectionCharge>? lastResidentCharges;

  void clear() {
    lastAdminCollections = null;
    lastResidentCharges = null;
  }

  Future<CollectionPreview> preview(CreateCollectionRequest request) {
    return _api.preview(request);
  }

  Future<CollectionSummary> create(CreateCollectionRequest request) async {
    final created = await _api.create(request);
    lastAdminCollections = null;
    return created;
  }

  Future<Paged<CollectionSummary>> listAdmin({
    String? status,
    String? search,
    bool force = false,
  }) async {
    if (!force && lastAdminCollections != null && status == null && search == null) {
      return lastAdminCollections!;
    }
    final page = await _api.listAdmin(status: status, search: search, limit: 50);
    if (status == null && search == null) lastAdminCollections = page;
    return page;
  }

  Future<CollectionSummary> adminCollection(String id) => _api.adminCollection(id);

  Future<CollectionSummary> update(
    String id, {
    String? title,
    String? description,
    String? dueDate,
    String? paymentInstructions,
    bool? allowPartialPayment,
  }) async {
    final updated = await _api.update(
      id,
      title: title,
      description: description,
      dueDate: dueDate,
      paymentInstructions: paymentInstructions,
      allowPartialPayment: allowPartialPayment,
    );
    lastAdminCollections = null;
    return updated;
  }

  Future<CollectionPreview> previewAddFlats(
    String id,
    AddCollectionFlatsRequest request,
  ) {
    return _api.previewAddFlats(id, request);
  }

  Future<CollectionSummary> addFlats(
    String id,
    AddCollectionFlatsRequest request,
  ) async {
    final result = await _api.addFlats(id, request);
    lastAdminCollections = null;
    return result;
  }

  Future<CollectionSummary> close(String id) async {
    final result = await _api.close(id);
    lastAdminCollections = null;
    return result;
  }

  Future<CollectionSummary> cancel(String id, {required String reason}) async {
    final result = await _api.cancel(id, reason: reason);
    lastAdminCollections = null;
    return result;
  }

  Future<CollectionDashboard> dashboard(String id) => _api.dashboard(id);

  Future<Paged<CollectionCharge>> listCharges(
    String collectionId, {
    CollectionChargeQuery query = const CollectionChargeQuery(),
  }) {
    return _api.listCharges(collectionId, query: query);
  }

  Future<List<int>> exportChargesCsv(String collectionId) {
    return _api.exportChargesCsv(collectionId);
  }

  Future<Paged<CollectionPayment>> listAdminPayments(
    String collectionId, {
    String? chargeId,
  }) {
    return _api.listAdminPayments(collectionId, chargeId: chargeId, limit: 50);
  }

  Future<CollectionCharge> adjustCharge(
    String chargeId, {
    required int deltaPaise,
    required String reason,
  }) {
    return _api.adjustCharge(chargeId, deltaPaise: deltaPaise, reason: reason);
  }

  Future<PaymentSettlement> recordOffline({
    required String chargeId,
    required int amountPaise,
    required String paidAt,
    required String referenceNumber,
    String? notes,
  }) {
    return _api.recordOffline(
      chargeId: chargeId,
      amountPaise: amountPaise,
      paidAt: paidAt,
      referenceNumber: referenceNumber,
      notes: notes,
    );
  }

  Future<CollectionReceiptDetail> adminReceipt(String receiptId) {
    return _api.adminReceipt(receiptId);
  }

  Future<CollectionReceiptDetail> adminPaymentReceipt(String paymentId) {
    return _api.adminPaymentReceipt(paymentId);
  }

  Future<List<CollectionCharge>> listResident({bool force = false}) async {
    if (!force && lastResidentCharges != null) return lastResidentCharges!;
    final items = await _api.listResident();
    lastResidentCharges = items;
    return items;
  }

  Future<CollectionCharge> residentCharge(String chargeId) {
    return _api.residentCharge(chargeId);
  }

  Future<CollectionPaymentOrderResult> createPaymentOrder(
    String chargeId, {
    int? amountPaise,
  }) {
    return _api.createPaymentOrder(chargeId, amountPaise: amountPaise);
  }

  Future<PaymentSettlement> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final result = await _api.verifyPayment(
      orderId: orderId,
      paymentId: paymentId,
      signature: signature,
    );
    lastResidentCharges = null;
    return result;
  }

  Future<PaymentSettlement> completeDemoPayment({
    required String orderId,
    required String outcome,
  }) async {
    final result = await _api.completeDemoPayment(orderId: orderId, outcome: outcome);
    lastResidentCharges = null;
    return result;
  }

  Future<Paged<CollectionPayment>> listResidentPayments({String? chargeId}) {
    return _api.listResidentPayments(chargeId: chargeId, limit: 50);
  }

  Future<CollectionReceiptDetail> residentReceipt(String receiptId) {
    return _api.residentReceipt(receiptId);
  }

  Future<CollectionReceiptDetail> residentPaymentReceipt(String paymentId) {
    return _api.residentPaymentReceipt(paymentId);
  }
}
