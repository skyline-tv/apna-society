import '../http/api_exception.dart';
import '../http/json_read.dart';
import 'billing_models.dart' show PaymentOrder;
import 'flat_label.dart';

class CollectionSummary {
  const CollectionSummary({
    required this.id,
    required this.collectionNumber,
    required this.title,
    required this.description,
    required this.amountMode,
    required this.assignmentType,
    required this.amountPaise,
    required this.allowPartialPayment,
    required this.dueDate,
    required this.status,
    required this.expectedTotalPaise,
    required this.collectedPaise,
    required this.outstandingPaise,
    required this.assignedFlatCount,
    required this.collectionPercentage,
    this.startDate,
    this.paymentInstructions,
    this.closedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.dashboard,
  });

  final String id;
  final String collectionNumber;
  final String title;
  final String description;
  final String amountMode;
  final String assignmentType;
  final int amountPaise;
  final bool allowPartialPayment;
  final String dueDate;
  final String? startDate;
  final String? paymentInstructions;
  final String status;
  final int expectedTotalPaise;
  final int collectedPaise;
  final int outstandingPaise;
  final int assignedFlatCount;
  final num collectionPercentage;
  final String? closedAt;
  final String? cancelledAt;
  final String? cancellationReason;
  final CollectionDashboard? dashboard;

  factory CollectionSummary.fromJson(Object? data) {
    final json = requireMap(data, 'collection');
    final percent = json['collectionPercentage'];
    if (percent is! num) {
      throw ApiParseException('Expected number collectionPercentage');
    }
    final dashboard = json['dashboard'];
    return CollectionSummary(
      id: requireString(json, 'id'),
      collectionNumber: requireString(json, 'collectionNumber'),
      title: requireString(json, 'title'),
      description: requireString(json, 'description'),
      amountMode: requireString(json, 'amountMode'),
      assignmentType: requireString(json, 'assignmentType'),
      amountPaise: requireInt(json, 'amountPaise'),
      allowPartialPayment: optionalBool(json, 'allowPartialPayment') ?? false,
      dueDate: requireString(json, 'dueDate'),
      startDate: optionalString(json, 'startDate'),
      paymentInstructions: optionalString(json, 'paymentInstructions'),
      status: requireString(json, 'status'),
      expectedTotalPaise: requireInt(json, 'expectedTotalPaise'),
      collectedPaise: requireInt(json, 'collectedPaise'),
      outstandingPaise: requireInt(json, 'outstandingPaise'),
      assignedFlatCount: requireInt(json, 'assignedFlatCount'),
      collectionPercentage: percent,
      closedAt: optionalString(json, 'closedAt'),
      cancelledAt: optionalString(json, 'cancelledAt'),
      cancellationReason: optionalString(json, 'cancellationReason'),
      dashboard: dashboard == null
          ? null
          : CollectionDashboard.fromJson(requireMap(dashboard, 'dashboard')),
    );
  }
}

class CollectionDashboard {
  const CollectionDashboard({
    required this.assignedFlatCount,
    required this.expectedTotalPaise,
    required this.collectedPaise,
    required this.outstandingPaise,
    required this.paidFlats,
    required this.partiallyPaidFlats,
    required this.pendingFlats,
    required this.overdueFlats,
    required this.collectionPercentage,
  });

  final int assignedFlatCount;
  final int expectedTotalPaise;
  final int collectedPaise;
  final int outstandingPaise;
  final int paidFlats;
  final int partiallyPaidFlats;
  final int pendingFlats;
  final int overdueFlats;
  final num collectionPercentage;

  factory CollectionDashboard.fromJson(Object? data) {
    final json = requireMap(data, 'dashboard');
    final percent = json['collectionPercentage'];
    if (percent is! num) {
      throw ApiParseException('Expected number collectionPercentage');
    }
    return CollectionDashboard(
      assignedFlatCount: requireInt(json, 'assignedFlatCount'),
      expectedTotalPaise: requireInt(json, 'expectedTotalPaise'),
      collectedPaise: requireInt(json, 'collectedPaise'),
      outstandingPaise: requireInt(json, 'outstandingPaise'),
      paidFlats: requireInt(json, 'paidFlats'),
      partiallyPaidFlats: requireInt(json, 'partiallyPaidFlats'),
      pendingFlats: requireInt(json, 'pendingFlats'),
      overdueFlats: requireInt(json, 'overdueFlats'),
      collectionPercentage: percent,
    );
  }
}

class CollectionCharge {
  const CollectionCharge({
    required this.id,
    required this.collectionId,
    required this.flatId,
    required this.amountPaise,
    required this.adjustmentsPaise,
    required this.assignedAmountPaise,
    required this.amountPaidPaise,
    required this.outstandingPaise,
    required this.status,
    required this.paymentStatus,
    required this.overdue,
    required this.dueDate,
    required this.wingCodeSnapshot,
    required this.flatNumberSnapshot,
    required this.occupancyStatusSnapshot,
    required this.ownerNameSnapshot,
    this.ownerUserId,
    this.collectionTitle,
    this.collectionNumber,
    this.collectionStatus,
    this.collectionDescription,
    this.allowPartialPayment = false,
    this.paymentInstructions,
    this.collection,
  });

  final String id;
  final String collectionId;
  final String flatId;
  final String? ownerUserId;
  final int amountPaise;
  final int adjustmentsPaise;
  final int assignedAmountPaise;
  final int amountPaidPaise;
  final int outstandingPaise;
  final String status;
  final String paymentStatus;
  final bool overdue;
  final String dueDate;
  final String wingCodeSnapshot;
  final String flatNumberSnapshot;
  final String occupancyStatusSnapshot;
  final String ownerNameSnapshot;
  final String? collectionTitle;
  final String? collectionNumber;
  final String? collectionStatus;
  final String? collectionDescription;
  final bool allowPartialPayment;
  final String? paymentInstructions;
  final CollectionSummary? collection;

  String get flatLabel =>
      formatFlatLabel(wingCodeSnapshot, flatNumberSnapshot);

  factory CollectionCharge.fromJson(Object? data) {
    final json = requireMap(data, 'collection charge');
    final collection = json['collection'];
    return CollectionCharge(
      id: requireString(json, 'id'),
      collectionId: requireString(json, 'collectionId'),
      flatId: requireString(json, 'flatId'),
      ownerUserId: optionalString(json, 'ownerUserId'),
      amountPaise: requireInt(json, 'amountPaise'),
      adjustmentsPaise: optionalInt(json, 'adjustmentsPaise') ?? 0,
      assignedAmountPaise: optionalInt(json, 'assignedAmountPaise') ??
          requireInt(json, 'amountPaise'),
      amountPaidPaise: requireInt(json, 'amountPaidPaise'),
      outstandingPaise: requireInt(json, 'outstandingPaise'),
      status: requireString(json, 'status'),
      paymentStatus: optionalString(json, 'paymentStatus') ??
          requireString(json, 'status'),
      overdue: optionalBool(json, 'overdue') ?? false,
      dueDate: requireString(json, 'dueDate'),
      wingCodeSnapshot: requireString(json, 'wingCodeSnapshot'),
      flatNumberSnapshot: requireString(json, 'flatNumberSnapshot'),
      occupancyStatusSnapshot: requireString(json, 'occupancyStatusSnapshot'),
      ownerNameSnapshot: requireString(json, 'ownerNameSnapshot'),
      collectionTitle: optionalString(json, 'collectionTitle'),
      collectionNumber: optionalString(json, 'collectionNumber'),
      collectionStatus: optionalString(json, 'collectionStatus'),
      collectionDescription: optionalString(json, 'collectionDescription'),
      allowPartialPayment: optionalBool(json, 'allowPartialPayment') ?? false,
      paymentInstructions: optionalString(json, 'paymentInstructions'),
      collection: collection == null
          ? null
          : CollectionSummary.fromJson(requireMap(collection, 'collection')),
    );
  }
}

class CollectionAllocation {
  const CollectionAllocation({
    required this.flatId,
    required this.flatLabel,
    required this.amountPaise,
    required this.occupancyStatus,
    required this.ownerName,
    required this.wingCode,
  });

  final String flatId;
  final String flatLabel;
  final int amountPaise;
  final String occupancyStatus;
  final String ownerName;
  final String wingCode;

  factory CollectionAllocation.fromJson(JsonMap json) {
    return CollectionAllocation(
      flatId: requireString(json, 'flatId'),
      flatLabel: requireString(json, 'flatLabel'),
      amountPaise: requireInt(json, 'amountPaise'),
      occupancyStatus: requireString(json, 'occupancyStatus'),
      ownerName: requireString(json, 'ownerName'),
      wingCode: requireString(json, 'wingCode'),
    );
  }
}

class CollectionPreview {
  const CollectionPreview({
    required this.assignedFlatCount,
    required this.amountMode,
    required this.assignmentType,
    required this.defaultAmountPaise,
    required this.expectedTotalPaise,
    required this.allocations,
    this.skippedAssignedCount = 0,
  });

  final int assignedFlatCount;
  final String amountMode;
  final String assignmentType;
  final int defaultAmountPaise;
  final int expectedTotalPaise;
  final List<CollectionAllocation> allocations;
  final int skippedAssignedCount;

  factory CollectionPreview.fromJson(Object? data) {
    final json = requireMap(data, 'collection preview');
    return CollectionPreview(
      assignedFlatCount: requireInt(json, 'assignedFlatCount'),
      amountMode: requireString(json, 'amountMode'),
      assignmentType: requireString(json, 'assignmentType'),
      defaultAmountPaise: requireInt(json, 'defaultAmountPaise'),
      expectedTotalPaise: requireInt(json, 'expectedTotalPaise'),
      allocations: requireMapList(json, 'allocations')
          .map(CollectionAllocation.fromJson)
          .toList(),
      skippedAssignedCount: optionalInt(json, 'skippedAssignedCount') ?? 0,
    );
  }
}

class AddCollectionFlatsRequest {
  const AddCollectionFlatsRequest({
    this.includeRemaining = false,
    this.wingIds,
    this.flatIds,
    this.flatAmounts,
    this.amountPaise,
  });

  final bool includeRemaining;
  final List<String>? wingIds;
  final List<String>? flatIds;
  final List<Map<String, Object?>>? flatAmounts;
  final int? amountPaise;

  Map<String, Object?> toJson() => omitNulls({
        'includeRemaining': includeRemaining ? true : null,
        'wingIds': wingIds,
        'flatIds': flatIds,
        'flatAmounts': flatAmounts,
        'amountPaise': amountPaise,
      });
}

class CollectionPayment {
  const CollectionPayment({
    required this.id,
    required this.paymentNumber,
    required this.collectionId,
    required this.chargeId,
    required this.amountPaise,
    required this.paymentMethod,
    required this.status,
    this.flatId,
    this.paidAt,
    this.referenceNumber,
    this.gatewayPaymentId,
    this.receiptId,
  });

  final String id;
  final String paymentNumber;
  final String collectionId;
  final String chargeId;
  final String? flatId;
  final int amountPaise;
  final String paymentMethod;
  final String status;
  final String? paidAt;
  final String? referenceNumber;
  final String? gatewayPaymentId;
  final String? receiptId;

  factory CollectionPayment.fromJson(JsonMap json) {
    return CollectionPayment(
      id: requireString(json, 'id'),
      paymentNumber: requireString(json, 'paymentNumber'),
      collectionId: requireString(json, 'collectionId'),
      chargeId: requireString(json, 'chargeId'),
      flatId: optionalString(json, 'flatId'),
      amountPaise: requireInt(json, 'amountPaise'),
      paymentMethod: requireString(json, 'paymentMethod'),
      status: requireString(json, 'status'),
      paidAt: optionalString(json, 'paidAt'),
      referenceNumber: optionalString(json, 'referenceNumber'),
      gatewayPaymentId: optionalString(json, 'gatewayPaymentId'),
      receiptId: optionalString(json, 'receiptId'),
    );
  }
}

class CollectionPaymentOrderResult {
  const CollectionPaymentOrderResult({
    required this.paymentId,
    required this.paymentNumber,
    required this.chargeId,
    required this.collectionId,
    required this.amountPaise,
    required this.order,
  });

  final String paymentId;
  final String paymentNumber;
  final String chargeId;
  final String collectionId;
  final int amountPaise;
  final PaymentOrder order;

  factory CollectionPaymentOrderResult.fromJson(Object? data) {
    final json = requireMap(data, 'collection payment order');
    return CollectionPaymentOrderResult(
      paymentId: requireString(json, 'paymentId'),
      paymentNumber: requireString(json, 'paymentNumber'),
      chargeId: requireString(json, 'chargeId'),
      collectionId: requireString(json, 'collectionId'),
      amountPaise: requireInt(json, 'amountPaise'),
      order: PaymentOrder.fromJson(requireMap(json['order'], 'order')),
    );
  }
}

class CollectionReceiptDetail {
  const CollectionReceiptDetail({
    required this.id,
    required this.receiptNumber,
    required this.collectionTitle,
    required this.collectionNumber,
    required this.amountPaise,
    required this.paymentMethod,
    required this.paidAt,
    required this.flatLabel,
    required this.ownerName,
    required this.pdfBase64,
    this.transactionReference,
    this.paymentId,
  });

  final String id;
  final String receiptNumber;
  final String collectionTitle;
  final String collectionNumber;
  final int amountPaise;
  final String paymentMethod;
  final String paidAt;
  final String flatLabel;
  final String ownerName;
  final String pdfBase64;
  final String? transactionReference;
  final String? paymentId;

  factory CollectionReceiptDetail.fromJson(Object? data) {
    final json = requireMap(data, 'collection receipt');
    final receipt = requireMap(json['receipt'], 'receipt');
    return CollectionReceiptDetail(
      id: requireString(receipt, 'id'),
      receiptNumber: requireString(receipt, 'receiptNumber'),
      collectionTitle: requireString(receipt, 'collectionTitleSnapshot'),
      collectionNumber: requireString(receipt, 'collectionNumberSnapshot'),
      amountPaise: requireInt(receipt, 'amountPaise'),
      paymentMethod: requireString(receipt, 'paymentMethod'),
      paidAt: requireString(receipt, 'paidAt'),
      flatLabel: optionalString(receipt, 'flatLabel') ??
          formatFlatLabel(
            requireString(receipt, 'wingCodeSnapshot'),
            requireString(receipt, 'flatNumberSnapshot'),
          ),
      ownerName: requireString(receipt, 'ownerNameSnapshot'),
      pdfBase64: requireString(json, 'pdfBase64'),
      transactionReference: optionalString(receipt, 'transactionReference'),
      paymentId: optionalString(receipt, 'paymentId'),
    );
  }
}

class CreateCollectionRequest {
  const CreateCollectionRequest({
    required this.title,
    required this.description,
    required this.amountMode,
    required this.assignmentType,
    required this.dueDate,
    required this.allowPartialPayment,
    this.amountPaise,
    this.wingIds,
    this.flatIds,
    this.flatAmounts,
    this.startDate,
    this.paymentInstructions,
  });

  final String title;
  final String description;
  final String amountMode;
  final String assignmentType;
  final int? amountPaise;
  final List<String>? wingIds;
  final List<String>? flatIds;
  final List<Map<String, Object?>>? flatAmounts;
  final String dueDate;
  final String? startDate;
  final String? paymentInstructions;
  final bool allowPartialPayment;

  Map<String, Object?> toJson() => omitNulls({
        'title': title,
        'description': description,
        'amountMode': amountMode,
        'assignmentType': assignmentType,
        'amountPaise': amountPaise,
        'wingIds': wingIds,
        'flatIds': flatIds,
        'flatAmounts': flatAmounts,
        'dueDate': dueDate,
        'startDate': startDate,
        'paymentInstructions': paymentInstructions,
        'allowPartialPayment': allowPartialPayment,
      });
}

class CollectionChargeQuery {
  const CollectionChargeQuery({
    this.wingCode,
    this.flatId,
    this.search,
    this.status,
    this.page,
    this.limit,
  });

  final String? wingCode;
  final String? flatId;
  final String? search;
  final String? status;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => omitNulls({
        'wingCode': wingCode,
        'flatId': flatId,
        'search': search,
        'status': status,
        'page': page,
        'limit': limit,
      });
}
