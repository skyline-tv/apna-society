import '../http/api_exception.dart';
import '../http/json_read.dart';

/// Backend-authoritative cap on [AdditionalService] rows with [isActive] true.
const kMaxActiveAdditionalServicesPerFlat = 10;
const kAdditionalServiceLimitCode = 'ADDITIONAL_SERVICE_LIMIT';
const kAdditionalServiceLimitMessage =
    'Maximum 10 active services allowed per flat.';

int activeAdditionalServiceCount(Iterable<AdditionalService> services) =>
    services.where((s) => s.isActive).length;

bool canAddActiveAdditionalService(Iterable<AdditionalService> services) =>
    activeAdditionalServiceCount(services) < kMaxActiveAdditionalServicesPerFlat;

class BillLineItem {
  const BillLineItem({
    required this.type,
    required this.name,
    required this.quantity,
    required this.unitAmountPaise,
    required this.amountPaise,
    this.serviceId,
    this.description,
    this.applicableDays,
    this.billedDays,
    this.prorationPolicy,
  });

  final String type;
  final String? serviceId;
  final String name;
  final String? description;
  final int quantity;
  final int unitAmountPaise;
  final int amountPaise;
  final int? applicableDays;
  final int? billedDays;
  final String? prorationPolicy;

  factory BillLineItem.fromJson(JsonMap json) {
    return BillLineItem(
      type: requireString(json, 'type'),
      serviceId: optionalString(json, 'serviceId'),
      name: requireString(json, 'name'),
      description: optionalString(json, 'description'),
      quantity: requireInt(json, 'quantity'),
      unitAmountPaise: requireInt(json, 'unitAmountPaise'),
      amountPaise: requireInt(json, 'amountPaise'),
      applicableDays: optionalInt(json, 'applicableDays'),
      billedDays: optionalInt(json, 'billedDays'),
      prorationPolicy: optionalString(json, 'prorationPolicy'),
    );
  }
}

class Bill {
  const Bill({
    required this.id,
    required this.billNumber,
    required this.flatId,
    required this.billingPeriodStart,
    required this.billingPeriodEnd,
    required this.numberOfMonths,
    required this.monthlyRatePaise,
    required this.baseAmountPaise,
    required this.totalAmountPaise,
    required this.outstandingPrincipalPaise,
    required this.interestAccruedPaise,
    required this.amountPaidPaise,
    required this.dueDate,
    required this.status,
    required this.flatNumberSnapshot,
    required this.wingCodeSnapshot,
    required this.flatTypeSnapshot,
    required this.ownerNameSnapshot,
    required this.ownerEmailSnapshot,
    this.ownerUserId,
    this.ownerAssigned = true,
    this.additionalServicesTotalPaise = 0,
    this.adjustmentsPaise = 0,
    this.lineItems = const [],
    this.occupancyStatusSnapshot,
    this.floorSnapshot,
    this.flatIsActiveSnapshot,
  });

  final String id;
  final String billNumber;
  final String flatId;
  final String? ownerUserId;
  final bool ownerAssigned;
  final String billingPeriodStart;
  final String billingPeriodEnd;
  final int numberOfMonths;
  final int monthlyRatePaise;
  final int baseAmountPaise;
  final int additionalServicesTotalPaise;
  final int adjustmentsPaise;
  final List<BillLineItem> lineItems;
  final int totalAmountPaise;
  final int outstandingPrincipalPaise;
  final int interestAccruedPaise;
  final int amountPaidPaise;
  final String dueDate;
  final String status;
  final String flatNumberSnapshot;
  final String wingCodeSnapshot;
  final String flatTypeSnapshot;
  final String? occupancyStatusSnapshot;
  final int? floorSnapshot;
  final bool? flatIsActiveSnapshot;
  final String ownerNameSnapshot;
  final String ownerEmailSnapshot;

  factory Bill.fromJson(Object? data) {
    final json = requireMap(data, 'bill');
    final items = json['lineItems'];
    return Bill(
      id: requireString(json, 'id'),
      billNumber: requireString(json, 'billNumber'),
      flatId: requireString(json, 'flatId'),
      ownerUserId: optionalString(json, 'ownerUserId'),
      ownerAssigned: optionalBool(json, 'ownerAssigned') ??
          (optionalString(json, 'ownerUserId') != null),
      billingPeriodStart: requireString(json, 'billingPeriodStart'),
      billingPeriodEnd: requireString(json, 'billingPeriodEnd'),
      numberOfMonths: requireInt(json, 'numberOfMonths'),
      monthlyRatePaise: requireInt(json, 'monthlyRatePaise'),
      baseAmountPaise: requireInt(json, 'baseAmountPaise'),
      additionalServicesTotalPaise:
          optionalInt(json, 'additionalServicesTotalPaise') ?? 0,
      adjustmentsPaise: optionalInt(json, 'adjustmentsPaise') ?? 0,
      lineItems: items is List
          ? items.map((item) => BillLineItem.fromJson(requireMap(item, 'lineItem'))).toList()
          : const [],
      totalAmountPaise: requireInt(json, 'totalAmountPaise'),
      outstandingPrincipalPaise: requireInt(json, 'outstandingPrincipalPaise'),
      interestAccruedPaise: requireInt(json, 'interestAccruedPaise'),
      amountPaidPaise: requireInt(json, 'amountPaidPaise'),
      dueDate: requireString(json, 'dueDate'),
      status: requireString(json, 'status'),
      flatNumberSnapshot: requireString(json, 'flatNumberSnapshot'),
      wingCodeSnapshot: requireString(json, 'wingCodeSnapshot'),
      flatTypeSnapshot: requireString(json, 'flatTypeSnapshot'),
      occupancyStatusSnapshot: optionalString(json, 'occupancyStatusSnapshot'),
      floorSnapshot: optionalInt(json, 'floorSnapshot'),
      flatIsActiveSnapshot: optionalBool(json, 'flatIsActiveSnapshot'),
      ownerNameSnapshot: requireString(json, 'ownerNameSnapshot'),
      ownerEmailSnapshot: requireString(json, 'ownerEmailSnapshot'),
    );
  }
}

class BillSkip {
  const BillSkip({required this.flatId, required this.number, required this.reason});
  final String flatId;
  final String number;
  final String reason;

  factory BillSkip.fromJson(JsonMap json) {
    return BillSkip(
      flatId: requireString(json, 'flatId'),
      number: requireString(json, 'number'),
      reason: requireString(json, 'reason'),
    );
  }
}

class BillConflict {
  const BillConflict({
    required this.flatId,
    required this.number,
    required this.reason,
    this.billId,
  });

  final String flatId;
  final String number;
  final String reason;
  final String? billId;

  factory BillConflict.fromJson(JsonMap json) {
    return BillConflict(
      flatId: requireString(json, 'flatId'),
      number: requireString(json, 'number'),
      reason: requireString(json, 'reason'),
      billId: optionalString(json, 'billId'),
    );
  }
}

class GenerateBillsResult {
  const GenerateBillsResult({
    required this.periodStart,
    required this.periodEnd,
    required this.dueDate,
    required this.numberOfMonths,
    required this.createdCount,
    required this.skippedCount,
    required this.conflictCount,
    required this.totalBilledPaise,
    required this.created,
    required this.skipped,
    required this.conflicts,
  });

  final String periodStart;
  final String periodEnd;
  final String dueDate;
  final int numberOfMonths;
  final int createdCount;
  final int skippedCount;
  final int conflictCount;
  final int totalBilledPaise;
  final List<Bill> created;
  final List<BillSkip> skipped;
  final List<BillConflict> conflicts;

  factory GenerateBillsResult.fromJson(Object? data) {
    final json = requireMap(data, 'generate bills');
    return GenerateBillsResult(
      periodStart: requireString(json, 'periodStart'),
      periodEnd: requireString(json, 'periodEnd'),
      dueDate: requireString(json, 'dueDate'),
      numberOfMonths: requireInt(json, 'numberOfMonths'),
      createdCount: requireInt(json, 'createdCount'),
      skippedCount: requireInt(json, 'skippedCount'),
      conflictCount: requireInt(json, 'conflictCount'),
      totalBilledPaise: requireInt(json, 'totalBilledPaise'),
      created: requireMapList(json, 'created').map(Bill.fromJson).toList(),
      skipped: requireMapList(json, 'skipped').map(BillSkip.fromJson).toList(),
      conflicts: requireMapList(json, 'conflicts').map(BillConflict.fromJson).toList(),
    );
  }
}

class InterestSegment {
  const InterestSegment({
    required this.from,
    required this.to,
    required this.days,
    required this.principalPaise,
    required this.interestPaise,
  });

  final String from;
  final String to;
  final int days;
  final int principalPaise;
  final int interestPaise;

  factory InterestSegment.fromJson(JsonMap json) {
    return InterestSegment(
      from: requireString(json, 'from'),
      to: requireString(json, 'to'),
      days: requireInt(json, 'days'),
      principalPaise: requireInt(json, 'principalPaise'),
      interestPaise: requireInt(json, 'interestPaise'),
    );
  }
}

class InterestBreakdown {
  const InterestBreakdown({
    required this.billId,
    required this.principalOutstandingPaise,
    required this.overdueDays,
    required this.annualInterestRateBps,
    required this.annualInterestRatePercent,
    required this.accruedInterestPaise,
    required this.asOf,
    required this.dueDate,
    required this.dayCountConvention,
    required this.rounding,
    required this.principalEffectiveConvention,
    required this.segments,
  });

  final String billId;
  final int principalOutstandingPaise;
  final int overdueDays;
  final int annualInterestRateBps;
  final num annualInterestRatePercent;
  final int accruedInterestPaise;
  final String asOf;
  final String dueDate;
  final String dayCountConvention;
  final String rounding;
  final String principalEffectiveConvention;
  final List<InterestSegment> segments;

  factory InterestBreakdown.fromJson(Object? data) {
    final json = requireMap(data, 'interest');
    final percent = json['annualInterestRatePercent'];
    if (percent is! num) {
      throw ApiParseException('Expected number annualInterestRatePercent');
    }
    return InterestBreakdown(
      billId: requireString(json, 'billId'),
      principalOutstandingPaise: requireInt(json, 'principalOutstandingPaise'),
      overdueDays: requireInt(json, 'overdueDays'),
      annualInterestRateBps: requireInt(json, 'annualInterestRateBps'),
      annualInterestRatePercent: percent,
      accruedInterestPaise: requireInt(json, 'accruedInterestPaise'),
      asOf: requireString(json, 'asOf'),
      dueDate: requireString(json, 'dueDate'),
      dayCountConvention: requireString(json, 'dayCountConvention'),
      rounding: requireString(json, 'rounding'),
      principalEffectiveConvention: requireString(json, 'principalEffectiveConvention'),
      segments: requireMapList(json, 'segments').map(InterestSegment.fromJson).toList(),
    );
  }
}

class EligibleFlat {
  const EligibleFlat({
    required this.id,
    required this.number,
    required this.wingCode,
    required this.flatType,
    required this.monthlyRatePaise,
    required this.occupancyStatus,
    this.ownerUserId,
    this.floor,
    this.isActive = true,
    this.ownerAssigned = false,
    this.recurringAdditionalPaise = 0,
    this.recurringMonthlyTotalPaise,
  });

  final String id;
  final String number;
  final String wingCode;
  final String flatType;
  final int monthlyRatePaise;
  final String? ownerUserId;
  final String occupancyStatus;
  final int? floor;
  final bool isActive;
  final bool ownerAssigned;
  final int recurringAdditionalPaise;
  final int? recurringMonthlyTotalPaise;

  factory EligibleFlat.fromJson(JsonMap json) {
    return EligibleFlat(
      id: requireString(json, 'id'),
      number: requireString(json, 'number'),
      wingCode: requireString(json, 'wingCode'),
      flatType: requireString(json, 'flatType'),
      monthlyRatePaise: requireInt(json, 'monthlyRatePaise'),
      ownerUserId: optionalString(json, 'ownerUserId'),
      occupancyStatus: requireString(json, 'occupancyStatus'),
      floor: optionalInt(json, 'floor'),
      isActive: optionalBool(json, 'isActive') ?? true,
      ownerAssigned: optionalBool(json, 'ownerAssigned') ??
          (optionalString(json, 'ownerUserId') != null),
      recurringAdditionalPaise:
          optionalInt(json, 'recurringAdditionalPaise') ?? 0,
      recurringMonthlyTotalPaise:
          optionalInt(json, 'recurringMonthlyTotalPaise'),
    );
  }
}

class PaymentOrder {
  const PaymentOrder({
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.provider,
    this.keyId,
  });

  final String orderId;
  final int amountPaise;
  final String currency;
  final String provider;
  final String? keyId;

  factory PaymentOrder.fromJson(JsonMap json) {
    return PaymentOrder(
      orderId: requireString(json, 'orderId'),
      amountPaise: requireInt(json, 'amountPaise'),
      currency: requireString(json, 'currency'),
      provider: requireString(json, 'provider'),
      keyId: optionalString(json, 'keyId'),
    );
  }
}

class CreatePaymentOrderResult {
  const CreatePaymentOrderResult({
    required this.paymentId,
    required this.paymentNumber,
    required this.billId,
    required this.amountPaise,
    required this.order,
  });

  final String paymentId;
  final String paymentNumber;
  final String billId;
  final int amountPaise;
  final PaymentOrder order;

  factory CreatePaymentOrderResult.fromJson(Object? data) {
    final json = requireMap(data, 'payment order');
    return CreatePaymentOrderResult(
      paymentId: requireString(json, 'paymentId'),
      paymentNumber: requireString(json, 'paymentNumber'),
      billId: requireString(json, 'billId'),
      amountPaise: requireInt(json, 'amountPaise'),
      order: PaymentOrder.fromJson(requireMap(json['order'], 'order')),
    );
  }
}

class PaymentSettlement {
  const PaymentSettlement({
    required this.paymentId,
    required this.alreadySettled,
    this.receiptId,
    this.billStatus,
    this.outstandingPrincipalPaise,
    this.ownerUserId,
  });

  final String paymentId;
  final bool alreadySettled;
  final String? receiptId;
  final String? billStatus;
  final int? outstandingPrincipalPaise;
  final String? ownerUserId;

  factory PaymentSettlement.fromJson(Object? data) {
    final json = requireMap(data, 'payment settlement');
    return PaymentSettlement(
      paymentId: requireString(json, 'paymentId'),
      alreadySettled: requireBool(json, 'alreadySettled'),
      receiptId: optionalString(json, 'receiptId'),
      billStatus: optionalString(json, 'billStatus'),
      outstandingPrincipalPaise: optionalInt(json, 'outstandingPrincipalPaise'),
      ownerUserId: optionalString(json, 'ownerUserId'),
    );
  }
}

class PaymentSummary {
  const PaymentSummary({
    required this.id,
    required this.paymentNumber,
    required this.billId,
    required this.amountPaise,
    required this.allocatedToPrincipalPaise,
    required this.allocatedToInterestPaise,
    required this.paymentMethod,
    required this.status,
    this.flatId,
    this.ownerUserId,
    this.paidAt,
    this.referenceNumber,
    this.gatewayOrderId,
    this.gatewayPaymentId,
  });

  final String id;
  final String paymentNumber;
  final String billId;
  final String? flatId;
  final String? ownerUserId;
  final int amountPaise;
  final int allocatedToPrincipalPaise;
  final int allocatedToInterestPaise;
  final String paymentMethod;
  final String status;
  final String? paidAt;
  final String? referenceNumber;
  final String? gatewayOrderId;
  final String? gatewayPaymentId;

  factory PaymentSummary.fromJson(JsonMap json) {
    return PaymentSummary(
      id: requireString(json, 'id'),
      paymentNumber: requireString(json, 'paymentNumber'),
      billId: requireString(json, 'billId'),
      flatId: optionalString(json, 'flatId'),
      ownerUserId: optionalString(json, 'ownerUserId'),
      amountPaise: requireInt(json, 'amountPaise'),
      allocatedToPrincipalPaise: requireInt(json, 'allocatedToPrincipalPaise'),
      allocatedToInterestPaise: requireInt(json, 'allocatedToInterestPaise'),
      paymentMethod: requireString(json, 'paymentMethod'),
      status: requireString(json, 'status'),
      paidAt: optionalString(json, 'paidAt'),
      referenceNumber: optionalString(json, 'referenceNumber'),
      gatewayOrderId: optionalString(json, 'gatewayOrderId'),
      gatewayPaymentId: optionalString(json, 'gatewayPaymentId'),
    );
  }
}

class ReceiptSummary {
  const ReceiptSummary({
    required this.id,
    required this.receiptNumber,
    required this.billId,
    required this.paymentId,
    required this.amountPaise,
    required this.paidAt,
    required this.flatNumberSnapshot,
    required this.wingCodeSnapshot,
  });

  final String id;
  final String receiptNumber;
  final String billId;
  final String paymentId;
  final int amountPaise;
  final String paidAt;
  final String flatNumberSnapshot;
  final String wingCodeSnapshot;

  factory ReceiptSummary.fromJson(JsonMap json) {
    return ReceiptSummary(
      id: requireString(json, 'id'),
      receiptNumber: requireString(json, 'receiptNumber'),
      billId: requireString(json, 'billId'),
      paymentId: requireString(json, 'paymentId'),
      amountPaise: requireInt(json, 'amountPaise'),
      paidAt: requireString(json, 'paidAt'),
      flatNumberSnapshot: requireString(json, 'flatNumberSnapshot'),
      wingCodeSnapshot: requireString(json, 'wingCodeSnapshot'),
    );
  }
}

class ReceiptDetail {
  const ReceiptDetail({
    required this.receipt,
    required this.pdfBase64,
  });

  final ReceiptBody receipt;
  final String pdfBase64;

  factory ReceiptDetail.fromJson(Object? data) {
    final json = requireMap(data, 'receipt');
    return ReceiptDetail(
      receipt: ReceiptBody.fromJson(requireMap(json['receipt'], 'receipt')),
      pdfBase64: requireString(json, 'pdfBase64'),
    );
  }
}

class ReceiptBody {
  const ReceiptBody({
    required this.id,
    required this.receiptNumber,
    required this.billId,
    required this.paymentId,
    required this.flatId,
    required this.amountPaise,
    required this.paymentMethod,
    required this.paidAt,
    required this.generatedAt,
    required this.ownerNameSnapshot,
    required this.flatNumberSnapshot,
    required this.wingCodeSnapshot,
    this.transactionReference,
  });

  final String id;
  final String receiptNumber;
  final String billId;
  final String paymentId;
  final String flatId;
  final int amountPaise;
  final String paymentMethod;
  final String paidAt;
  final String generatedAt;
  final String ownerNameSnapshot;
  final String flatNumberSnapshot;
  final String wingCodeSnapshot;
  final String? transactionReference;

  factory ReceiptBody.fromJson(JsonMap json) {
    return ReceiptBody(
      id: requireString(json, 'id'),
      receiptNumber: requireString(json, 'receiptNumber'),
      billId: requireString(json, 'billId'),
      paymentId: requireString(json, 'paymentId'),
      flatId: requireString(json, 'flatId'),
      amountPaise: requireInt(json, 'amountPaise'),
      paymentMethod: requireString(json, 'paymentMethod'),
      paidAt: requireString(json, 'paidAt'),
      generatedAt: requireString(json, 'generatedAt'),
      ownerNameSnapshot: requireString(json, 'ownerNameSnapshot'),
      flatNumberSnapshot: requireString(json, 'flatNumberSnapshot'),
      wingCodeSnapshot: requireString(json, 'wingCodeSnapshot'),
      transactionReference: optionalString(json, 'transactionReference'),
    );
  }
}

class BillingWingTotal {
  const BillingWingTotal({
    required this.wingCode,
    required this.billedPaise,
    required this.collectedPaise,
    required this.outstandingPrincipalPaise,
    required this.billCount,
  });

  final String wingCode;
  final int billedPaise;
  final int collectedPaise;
  final int outstandingPrincipalPaise;
  final int billCount;

  factory BillingWingTotal.fromJson(JsonMap json) {
    return BillingWingTotal(
      wingCode: requireString(json, 'wingCode'),
      billedPaise: requireInt(json, 'billedPaise'),
      collectedPaise: requireInt(json, 'collectedPaise'),
      outstandingPrincipalPaise: requireInt(json, 'outstandingPrincipalPaise'),
      billCount: requireInt(json, 'billCount'),
    );
  }
}

class PaymentStatusTotal {
  const PaymentStatusTotal({required this.count, required this.amountPaise});
  final int count;
  final int amountPaise;

  factory PaymentStatusTotal.fromJson(JsonMap json) {
    return PaymentStatusTotal(
      count: requireInt(json, 'count'),
      amountPaise: requireInt(json, 'amountPaise'),
    );
  }
}

class BillingSummary {
  const BillingSummary({
    required this.totalBilledPaise,
    required this.totalCollectedPaise,
    required this.totalOutstandingPrincipalPaise,
    required this.totalAccruedInterestPaise,
    required this.paidBills,
    required this.partiallyPaidBills,
    required this.overdueBills,
    required this.issuedBills,
    required this.cancelledBills,
    required this.vacantOrUnassignedFlatsSkipped,
    required this.collectionPercentage,
    required this.billCount,
    required this.wingWise,
    required this.paymentsByStatus,
    this.totalConfiguredFlats = 0,
    this.totalMaintenanceBilledPaise = 0,
    this.totalAdditionalServicesBilledPaise = 0,
    this.pendingBills = 0,
    this.vacantFlatBills = 0,
    this.unassignedFlatBills = 0,
  });

  final int totalConfiguredFlats;
  final int totalBilledPaise;
  final int totalMaintenanceBilledPaise;
  final int totalAdditionalServicesBilledPaise;
  final int totalCollectedPaise;
  final int totalOutstandingPrincipalPaise;
  final int totalAccruedInterestPaise;
  final int paidBills;
  final int partiallyPaidBills;
  final int pendingBills;
  final int overdueBills;
  final int issuedBills;
  final int cancelledBills;
  final int vacantFlatBills;
  final int unassignedFlatBills;
  final int vacantOrUnassignedFlatsSkipped;
  final num collectionPercentage;
  final int billCount;
  final List<BillingWingTotal> wingWise;
  final Map<String, PaymentStatusTotal> paymentsByStatus;

  factory BillingSummary.fromJson(Object? data) {
    final json = requireMap(data, 'billing summary');
    final percent = json['collectionPercentage'];
    if (percent is! num) {
      throw ApiParseException('Expected number collectionPercentage');
    }
    final byStatus = json['paymentsByStatus'];
    if (byStatus is! Map) {
      throw ApiParseException('Expected object paymentsByStatus');
    }
    return BillingSummary(
      totalConfiguredFlats: optionalInt(json, 'totalConfiguredFlats') ?? 0,
      totalBilledPaise: requireInt(json, 'totalBilledPaise'),
      totalMaintenanceBilledPaise:
          optionalInt(json, 'totalMaintenanceBilledPaise') ?? 0,
      totalAdditionalServicesBilledPaise:
          optionalInt(json, 'totalAdditionalServicesBilledPaise') ?? 0,
      totalCollectedPaise: requireInt(json, 'totalCollectedPaise'),
      totalOutstandingPrincipalPaise: requireInt(json, 'totalOutstandingPrincipalPaise'),
      totalAccruedInterestPaise: requireInt(json, 'totalAccruedInterestPaise'),
      paidBills: requireInt(json, 'paidBills'),
      partiallyPaidBills: requireInt(json, 'partiallyPaidBills'),
      pendingBills: optionalInt(json, 'pendingBills') ??
          requireInt(json, 'issuedBills') +
              requireInt(json, 'partiallyPaidBills'),
      overdueBills: requireInt(json, 'overdueBills'),
      issuedBills: requireInt(json, 'issuedBills'),
      cancelledBills: requireInt(json, 'cancelledBills'),
      vacantFlatBills: optionalInt(json, 'vacantFlatBills') ?? 0,
      unassignedFlatBills: optionalInt(json, 'unassignedFlatBills') ?? 0,
      vacantOrUnassignedFlatsSkipped: requireInt(json, 'vacantOrUnassignedFlatsSkipped'),
      collectionPercentage: percent,
      billCount: requireInt(json, 'billCount'),
      wingWise: requireMapList(json, 'wingWise').map(BillingWingTotal.fromJson).toList(),
      paymentsByStatus: byStatus.map(
        (key, value) => MapEntry(
          key.toString(),
          PaymentStatusTotal.fromJson(requireMap(value, 'paymentsByStatus')),
        ),
      ),
    );
  }
}

class ListBillsQuery {
  const ListBillsQuery({
    this.status,
    this.flatId,
    this.ownerUserId,
    this.wingCode,
    this.billingPeriodStart,
    this.occupancyStatus,
    this.floor,
    this.ownerAssigned,
    this.page,
    this.limit,
  });

  final String? status;
  final String? flatId;
  final String? ownerUserId;
  final String? wingCode;
  final String? billingPeriodStart;
  final String? occupancyStatus;
  final int? floor;
  final bool? ownerAssigned;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'status': status,
        'flatId': flatId,
        'ownerUserId': ownerUserId,
        'wingCode': wingCode,
        'billingPeriodStart': billingPeriodStart,
        'occupancyStatus': occupancyStatus,
        'floor': floor,
        'ownerAssigned': ownerAssigned?.toString(),
        'page': page,
        'limit': limit,
      };
}

class AdditionalService {
  const AdditionalService({
    required this.id,
    required this.societyId,
    required this.flatId,
    required this.name,
    required this.monthlyChargePaise,
    required this.quantity,
    required this.monthlyTotalPaise,
    required this.effectiveFrom,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.effectiveTo,
    this.flatNumber,
    this.wingCode,
    this.floor,
    this.deactivatedAt,
    this.deactivationReason,
  });

  final String id;
  final String societyId;
  final String flatId;
  final String name;
  final String? description;
  final int monthlyChargePaise;
  final int quantity;
  final int monthlyTotalPaise;
  final String effectiveFrom;
  final String? effectiveTo;
  final bool isActive;
  final String createdAt;
  final String updatedAt;
  final String? flatNumber;
  final String? wingCode;
  final int? floor;
  final String? deactivatedAt;
  final String? deactivationReason;

  factory AdditionalService.fromJson(Object? data) {
    final json = requireMap(data, 'additional service');
    return AdditionalService(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      flatId: requireString(json, 'flatId'),
      name: requireString(json, 'name'),
      description: optionalString(json, 'description'),
      monthlyChargePaise: requireInt(json, 'monthlyChargePaise'),
      quantity: requireInt(json, 'quantity'),
      monthlyTotalPaise: requireInt(json, 'monthlyTotalPaise'),
      effectiveFrom: requireString(json, 'effectiveFrom'),
      effectiveTo: optionalString(json, 'effectiveTo'),
      isActive: requireBool(json, 'isActive'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
      flatNumber: optionalString(json, 'flatNumber'),
      wingCode: optionalString(json, 'wingCode'),
      floor: optionalInt(json, 'floor'),
      deactivatedAt: optionalString(json, 'deactivatedAt'),
      deactivationReason: optionalString(json, 'deactivationReason'),
    );
  }
}

class CreateAdditionalServiceRequest {
  const CreateAdditionalServiceRequest({
    required this.flatId,
    required this.name,
    required this.monthlyChargePaise,
    required this.quantity,
    required this.effectiveFrom,
    this.description,
    this.effectiveTo,
  });

  final String flatId;
  final String name;
  final String? description;
  final int monthlyChargePaise;
  final int quantity;
  final String effectiveFrom;
  final String? effectiveTo;

  Map<String, Object?> toJson() => omitNulls({
        'flatId': flatId,
        'name': name,
        'description': description,
        'monthlyChargePaise': monthlyChargePaise,
        'quantity': quantity,
        'effectiveFrom': effectiveFrom,
        'effectiveTo': effectiveTo,
      });
}

class UpdateAdditionalServiceRequest {
  const UpdateAdditionalServiceRequest({
    this.name,
    this.description,
    this.monthlyChargePaise,
    this.quantity,
    this.effectiveFrom,
    this.effectiveTo,
    this.clearEffectiveTo = false,
    this.isActive,
  });

  final String? name;
  final String? description;
  final int? monthlyChargePaise;
  final int? quantity;
  final String? effectiveFrom;
  final String? effectiveTo;
  final bool clearEffectiveTo;
  final bool? isActive;

  Map<String, Object?> toJson() {
    final map = omitNulls({
      'name': name,
      'description': description,
      'monthlyChargePaise': monthlyChargePaise,
      'quantity': quantity,
      'effectiveFrom': effectiveFrom,
      'effectiveTo': effectiveTo,
      'isActive': isActive,
    });
    if (clearEffectiveTo) map['effectiveTo'] = null;
    return map;
  }
}

class InterestRefreshResult {
  const InterestRefreshResult({required this.updated});
  final int updated;

  factory InterestRefreshResult.fromJson(Object? data) {
    final json = requireMap(data, 'interest refresh');
    return InterestRefreshResult(updated: requireInt(json, 'updated'));
  }
}

/// Principal + accrued interest still due (server paise values).
int billAmountDuePaise(Bill bill) =>
    bill.outstandingPrincipalPaise + bill.interestAccruedPaise;
