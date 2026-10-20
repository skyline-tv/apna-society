import '../http/api_exception.dart';
import '../http/json_read.dart';
import 'common.dart';

class MoneyPeriodPoint {
  const MoneyPeriodPoint({
    required this.year,
    required this.billedPaise,
    required this.collectedPaise,
    required this.outstandingPrincipalPaise,
    required this.billCount,
    this.month,
    this.accruedInterestPaise,
    this.collectionPercentage,
  });

  final int year;
  final int? month;
  final int billedPaise;
  final int collectedPaise;
  final int outstandingPrincipalPaise;
  final int? accruedInterestPaise;
  final int billCount;
  final num? collectionPercentage;

  factory MoneyPeriodPoint.fromJson(JsonMap json) {
    final percent = json['collectionPercentage'];
    if (percent != null && percent is! num) {
      throw ApiParseException('Expected number collectionPercentage');
    }
    return MoneyPeriodPoint(
      year: requireInt(json, 'year'),
      month: optionalInt(json, 'month'),
      billedPaise: requireInt(json, 'billedPaise'),
      collectedPaise: requireInt(json, 'collectedPaise'),
      outstandingPrincipalPaise: requireInt(json, 'outstandingPrincipalPaise'),
      accruedInterestPaise: optionalInt(json, 'accruedInterestPaise'),
      billCount: requireInt(json, 'billCount'),
      collectionPercentage: percent as num?,
    );
  }
}

class FinancialReport {
  const FinancialReport({
    required this.from,
    required this.to,
    required this.totalBilledPaise,
    required this.totalCollectedPaise,
    required this.totalOutstandingPrincipalPaise,
    required this.totalAccruedInterestPaise,
    required this.totalRefundsPaise,
    required this.totalOfflineCollectionsPaise,
    required this.totalOnlineCollectionsPaise,
    required this.paymentSuccessCount,
    required this.paymentFailureCount,
    required this.paymentRefundedCount,
    required this.paymentPendingCount,
    required this.billCount,
    required this.collectionPercentage,
    required this.monthly,
    required this.yearly,
    required this.note,
    this.wingCode,
    this.flatId,
  });

  final String from;
  final String to;
  final String? wingCode;
  final String? flatId;
  final int totalBilledPaise;
  final int totalCollectedPaise;
  final int totalOutstandingPrincipalPaise;
  final int totalAccruedInterestPaise;
  final int totalRefundsPaise;
  final int totalOfflineCollectionsPaise;
  final int totalOnlineCollectionsPaise;
  final int paymentSuccessCount;
  final int paymentFailureCount;
  final int paymentRefundedCount;
  final int paymentPendingCount;
  final int billCount;
  final num collectionPercentage;
  final List<MoneyPeriodPoint> monthly;
  final List<MoneyPeriodPoint> yearly;
  final String note;

  factory FinancialReport.fromJson(Object? data) {
    final json = requireMap(data, 'financial report');
    final percent = json['collectionPercentage'];
    if (percent is! num) {
      throw ApiParseException('Expected number collectionPercentage');
    }
    return FinancialReport(
      from: requireString(json, 'from'),
      to: requireString(json, 'to'),
      wingCode: optionalString(json, 'wingCode'),
      flatId: optionalString(json, 'flatId'),
      totalBilledPaise: requireInt(json, 'totalBilledPaise'),
      totalCollectedPaise: requireInt(json, 'totalCollectedPaise'),
      totalOutstandingPrincipalPaise: requireInt(json, 'totalOutstandingPrincipalPaise'),
      totalAccruedInterestPaise: requireInt(json, 'totalAccruedInterestPaise'),
      totalRefundsPaise: requireInt(json, 'totalRefundsPaise'),
      totalOfflineCollectionsPaise: requireInt(json, 'totalOfflineCollectionsPaise'),
      totalOnlineCollectionsPaise: requireInt(json, 'totalOnlineCollectionsPaise'),
      paymentSuccessCount: requireInt(json, 'paymentSuccessCount'),
      paymentFailureCount: requireInt(json, 'paymentFailureCount'),
      paymentRefundedCount: requireInt(json, 'paymentRefundedCount'),
      paymentPendingCount: requireInt(json, 'paymentPendingCount'),
      billCount: requireInt(json, 'billCount'),
      collectionPercentage: percent,
      monthly: requireMapList(json, 'monthly').map(MoneyPeriodPoint.fromJson).toList(),
      yearly: requireMapList(json, 'yearly').map(MoneyPeriodPoint.fromJson).toList(),
      note: requireString(json, 'note'),
    );
  }
}

class WingCollection {
  const WingCollection({
    required this.wingCode,
    required this.billedPaise,
    required this.collectedPaise,
    required this.outstandingPrincipalPaise,
    required this.billCount,
    required this.collectionPercentage,
  });

  final String wingCode;
  final int billedPaise;
  final int collectedPaise;
  final int outstandingPrincipalPaise;
  final int billCount;
  final num collectionPercentage;

  factory WingCollection.fromJson(JsonMap json) {
    final percent = json['collectionPercentage'];
    if (percent is! num) {
      throw ApiParseException('Expected number collectionPercentage');
    }
    return WingCollection(
      wingCode: requireString(json, 'wingCode'),
      billedPaise: requireInt(json, 'billedPaise'),
      collectedPaise: requireInt(json, 'collectedPaise'),
      outstandingPrincipalPaise: requireInt(json, 'outstandingPrincipalPaise'),
      billCount: requireInt(json, 'billCount'),
      collectionPercentage: percent,
    );
  }
}

class CollectionReport {
  const CollectionReport({
    required this.from,
    required this.to,
    required this.totalBillsGenerated,
    required this.totalAmountCollectedPaise,
    required this.totalAmountOutstandingPaise,
    required this.totalBilledPaise,
    required this.paidBills,
    required this.partiallyPaidBills,
    required this.unpaidBills,
    required this.overdueBills,
    required this.collectionPercentage,
    required this.collectionPercentageFormula,
    required this.wingWise,
    required this.monthlyTrends,
    this.wingCode,
    this.flatId,
  });

  final String from;
  final String to;
  final String? wingCode;
  final String? flatId;
  final int totalBillsGenerated;
  final int totalAmountCollectedPaise;
  final int totalAmountOutstandingPaise;
  final int totalBilledPaise;
  final int paidBills;
  final int partiallyPaidBills;
  final int unpaidBills;
  final int overdueBills;
  final num collectionPercentage;
  final String collectionPercentageFormula;
  final List<WingCollection> wingWise;
  final List<MoneyPeriodPoint> monthlyTrends;

  factory CollectionReport.fromJson(Object? data) {
    final json = requireMap(data, 'collection report');
    final percent = json['collectionPercentage'];
    if (percent is! num) {
      throw ApiParseException('Expected number collectionPercentage');
    }
    return CollectionReport(
      from: requireString(json, 'from'),
      to: requireString(json, 'to'),
      wingCode: optionalString(json, 'wingCode'),
      flatId: optionalString(json, 'flatId'),
      totalBillsGenerated: requireInt(json, 'totalBillsGenerated'),
      totalAmountCollectedPaise: requireInt(json, 'totalAmountCollectedPaise'),
      totalAmountOutstandingPaise: requireInt(json, 'totalAmountOutstandingPaise'),
      totalBilledPaise: requireInt(json, 'totalBilledPaise'),
      paidBills: requireInt(json, 'paidBills'),
      partiallyPaidBills: requireInt(json, 'partiallyPaidBills'),
      unpaidBills: requireInt(json, 'unpaidBills'),
      overdueBills: requireInt(json, 'overdueBills'),
      collectionPercentage: percent,
      collectionPercentageFormula: requireString(json, 'collectionPercentageFormula'),
      wingWise: requireMapList(json, 'wingWise').map(WingCollection.fromJson).toList(),
      monthlyTrends:
          requireMapList(json, 'monthlyTrends').map(MoneyPeriodPoint.fromJson).toList(),
    );
  }
}

class OutstandingFlat {
  const OutstandingFlat({
    required this.flatId,
    required this.wingCode,
    required this.flatNumber,
    required this.ownerNameSnapshot,
    required this.billedPaise,
    required this.collectedPaise,
    required this.outstandingPrincipalPaise,
    required this.accruedInterestPaise,
    required this.billCount,
  });

  final String flatId;
  final String wingCode;
  final String flatNumber;
  final String ownerNameSnapshot;
  final int billedPaise;
  final int collectedPaise;
  final int outstandingPrincipalPaise;
  final int accruedInterestPaise;
  final int billCount;

  factory OutstandingFlat.fromJson(JsonMap json) {
    return OutstandingFlat(
      flatId: requireString(json, 'flatId'),
      wingCode: requireString(json, 'wingCode'),
      flatNumber: requireString(json, 'flatNumber'),
      ownerNameSnapshot: requireString(json, 'ownerNameSnapshot'),
      billedPaise: requireInt(json, 'billedPaise'),
      collectedPaise: requireInt(json, 'collectedPaise'),
      outstandingPrincipalPaise: requireInt(json, 'outstandingPrincipalPaise'),
      accruedInterestPaise: requireInt(json, 'accruedInterestPaise'),
      billCount: requireInt(json, 'billCount'),
    );
  }
}

class OutstandingReport {
  const OutstandingReport({
    required this.from,
    required this.to,
    required this.items,
    required this.outstandingPrincipalPaise,
    required this.accruedInterestPaise,
    required this.flatCount,
    required this.pagination,
    this.wingCode,
  });

  final String from;
  final String to;
  final String? wingCode;
  final List<OutstandingFlat> items;
  final int outstandingPrincipalPaise;
  final int accruedInterestPaise;
  final int flatCount;
  final Page pagination;

  factory OutstandingReport.fromJson(Object? data) {
    final json = requireMap(data, 'outstanding report');
    final totals = requireMap(json['totals'], 'totals');
    return OutstandingReport(
      from: requireString(json, 'from'),
      to: requireString(json, 'to'),
      wingCode: optionalString(json, 'wingCode'),
      items: requireMapList(json, 'items').map(OutstandingFlat.fromJson).toList(),
      outstandingPrincipalPaise: requireInt(totals, 'outstandingPrincipalPaise'),
      accruedInterestPaise: requireInt(totals, 'accruedInterestPaise'),
      flatCount: requireInt(totals, 'flatCount'),
      pagination: Page.fromJson(requireMap(json['pagination'], 'pagination')),
    );
  }
}

class ComplaintTrend {
  const ComplaintTrend({required this.year, required this.month, required this.count});
  final int year;
  final int month;
  final int count;

  factory ComplaintTrend.fromJson(JsonMap json) {
    return ComplaintTrend(
      year: requireInt(json, 'year'),
      month: requireInt(json, 'month'),
      count: requireInt(json, 'count'),
    );
  }
}

class ComplaintWingCount {
  const ComplaintWingCount({required this.wingCode, required this.count});
  final String wingCode;
  final int count;

  factory ComplaintWingCount.fromJson(JsonMap json) {
    return ComplaintWingCount(
      wingCode: requireString(json, 'wingCode'),
      count: requireInt(json, 'count'),
    );
  }
}

class ComplaintWorkload {
  const ComplaintWorkload({
    required this.assignedToName,
    required this.openAssigned,
    this.assignedToUserId,
  });

  final String? assignedToUserId;
  final String assignedToName;
  final int openAssigned;

  factory ComplaintWorkload.fromJson(JsonMap json) {
    return ComplaintWorkload(
      assignedToUserId: optionalString(json, 'assignedToUserId'),
      assignedToName: requireString(json, 'assignedToName'),
      openAssigned: requireInt(json, 'openAssigned'),
    );
  }
}

class ComplaintReport {
  const ComplaintReport({
    required this.from,
    required this.to,
    required this.totalComplaints,
    required this.open,
    required this.assigned,
    required this.inProgress,
    required this.resolved,
    required this.closed,
    required this.cancelled,
    required this.byCategory,
    required this.byPriority,
    required this.byWing,
    required this.resolvedWithTimestampCount,
    required this.trends,
    required this.workload,
    required this.note,
    this.wingCode,
    this.flatId,
    this.averageResolutionHours,
  });

  final String from;
  final String to;
  final String? wingCode;
  final String? flatId;
  final int totalComplaints;
  final int open;
  final int assigned;
  final int inProgress;
  final int resolved;
  final int closed;
  final int cancelled;
  final Map<String, int> byCategory;
  final Map<String, int> byPriority;
  final List<ComplaintWingCount> byWing;
  final double? averageResolutionHours;
  final int resolvedWithTimestampCount;
  final List<ComplaintTrend> trends;
  final List<ComplaintWorkload> workload;
  final String note;

  factory ComplaintReport.fromJson(Object? data) {
    final json = requireMap(data, 'complaint report');
    return ComplaintReport(
      from: requireString(json, 'from'),
      to: requireString(json, 'to'),
      wingCode: optionalString(json, 'wingCode'),
      flatId: optionalString(json, 'flatId'),
      totalComplaints: requireInt(json, 'totalComplaints'),
      open: requireInt(json, 'open'),
      assigned: requireInt(json, 'assigned'),
      inProgress: requireInt(json, 'inProgress'),
      resolved: requireInt(json, 'resolved'),
      closed: requireInt(json, 'closed'),
      cancelled: requireInt(json, 'cancelled'),
      byCategory: requireIntMap(json, 'byCategory'),
      byPriority: requireIntMap(json, 'byPriority'),
      byWing: requireMapList(json, 'byWing').map(ComplaintWingCount.fromJson).toList(),
      averageResolutionHours: optionalDouble(json, 'averageResolutionHours'),
      resolvedWithTimestampCount: requireInt(json, 'resolvedWithTimestampCount'),
      trends: requireMapList(json, 'trends').map(ComplaintTrend.fromJson).toList(),
      workload: requireMapList(json, 'workload').map(ComplaintWorkload.fromJson).toList(),
      note: requireString(json, 'note'),
    );
  }
}

class ReportsDashboardFinancial {
  const ReportsDashboardFinancial({
    required this.totalBilledPaise,
    required this.totalCollectedPaise,
    required this.totalOutstandingPrincipalPaise,
    required this.totalAccruedInterestPaise,
    required this.totalRefundsPaise,
    required this.totalOfflineCollectionsPaise,
    required this.totalOnlineCollectionsPaise,
    required this.paymentSuccessCount,
    required this.paymentFailureCount,
    required this.collectionPercentage,
  });

  final int totalBilledPaise;
  final int totalCollectedPaise;
  final int totalOutstandingPrincipalPaise;
  final int totalAccruedInterestPaise;
  final int totalRefundsPaise;
  final int totalOfflineCollectionsPaise;
  final int totalOnlineCollectionsPaise;
  final int paymentSuccessCount;
  final int paymentFailureCount;
  final num collectionPercentage;

  factory ReportsDashboardFinancial.fromJson(JsonMap json) {
    final percent = json['collectionPercentage'];
    if (percent is! num) {
      throw ApiParseException('Expected number collectionPercentage');
    }
    return ReportsDashboardFinancial(
      totalBilledPaise: requireInt(json, 'totalBilledPaise'),
      totalCollectedPaise: requireInt(json, 'totalCollectedPaise'),
      totalOutstandingPrincipalPaise:
          requireInt(json, 'totalOutstandingPrincipalPaise'),
      totalAccruedInterestPaise: requireInt(json, 'totalAccruedInterestPaise'),
      totalRefundsPaise: requireInt(json, 'totalRefundsPaise'),
      totalOfflineCollectionsPaise:
          requireInt(json, 'totalOfflineCollectionsPaise'),
      totalOnlineCollectionsPaise:
          requireInt(json, 'totalOnlineCollectionsPaise'),
      paymentSuccessCount: requireInt(json, 'paymentSuccessCount'),
      paymentFailureCount: requireInt(json, 'paymentFailureCount'),
      collectionPercentage: percent,
    );
  }
}

class ReportsDashboardCollections {
  const ReportsDashboardCollections({
    required this.totalBillsGenerated,
    required this.paidBills,
    required this.partiallyPaidBills,
    required this.unpaidBills,
    required this.overdueBills,
    required this.collectionPercentage,
    required this.wingWise,
  });

  final int totalBillsGenerated;
  final int paidBills;
  final int partiallyPaidBills;
  final int unpaidBills;
  final int overdueBills;
  final num collectionPercentage;
  final List<WingCollection> wingWise;

  factory ReportsDashboardCollections.fromJson(JsonMap json) {
    final percent = json['collectionPercentage'];
    if (percent is! num) {
      throw ApiParseException('Expected number collectionPercentage');
    }
    return ReportsDashboardCollections(
      totalBillsGenerated: requireInt(json, 'totalBillsGenerated'),
      paidBills: requireInt(json, 'paidBills'),
      partiallyPaidBills: requireInt(json, 'partiallyPaidBills'),
      unpaidBills: requireInt(json, 'unpaidBills'),
      overdueBills: requireInt(json, 'overdueBills'),
      collectionPercentage: percent,
      wingWise:
          requireMapList(json, 'wingWise').map(WingCollection.fromJson).toList(),
    );
  }
}

class ReportsDashboardComplaints {
  const ReportsDashboardComplaints({
    required this.totalComplaints,
    required this.open,
    required this.assigned,
    required this.inProgress,
    required this.resolved,
    required this.closed,
    required this.cancelled,
    required this.byCategory,
    this.averageResolutionHours,
  });

  final int totalComplaints;
  final int open;
  final int assigned;
  final int inProgress;
  final int resolved;
  final int closed;
  final int cancelled;
  final double? averageResolutionHours;
  final Map<String, int> byCategory;

  factory ReportsDashboardComplaints.fromJson(JsonMap json) {
    return ReportsDashboardComplaints(
      totalComplaints: requireInt(json, 'totalComplaints'),
      open: requireInt(json, 'open'),
      assigned: requireInt(json, 'assigned'),
      inProgress: requireInt(json, 'inProgress'),
      resolved: requireInt(json, 'resolved'),
      closed: requireInt(json, 'closed'),
      cancelled: requireInt(json, 'cancelled'),
      averageResolutionHours: optionalDouble(json, 'averageResolutionHours'),
      byCategory: requireIntMap(json, 'byCategory'),
    );
  }
}

class ReportsDashboardOutstandingTotals {
  const ReportsDashboardOutstandingTotals({
    required this.outstandingPrincipalPaise,
    required this.accruedInterestPaise,
    required this.flatCount,
  });

  final int outstandingPrincipalPaise;
  final int accruedInterestPaise;
  final int flatCount;

  factory ReportsDashboardOutstandingTotals.fromJson(JsonMap json) {
    return ReportsDashboardOutstandingTotals(
      outstandingPrincipalPaise: requireInt(json, 'outstandingPrincipalPaise'),
      accruedInterestPaise: requireInt(json, 'accruedInterestPaise'),
      flatCount: requireInt(json, 'flatCount'),
    );
  }
}

class ReportsDashboard {
  const ReportsDashboard({
    required this.from,
    required this.to,
    required this.financial,
    required this.collections,
    required this.outstandingTotals,
    required this.topFlats,
    required this.complaints,
    this.wingCode,
  });

  final String from;
  final String to;
  final String? wingCode;
  final ReportsDashboardFinancial financial;
  final ReportsDashboardCollections collections;
  final ReportsDashboardOutstandingTotals outstandingTotals;
  final List<OutstandingFlat> topFlats;
  final ReportsDashboardComplaints complaints;

  factory ReportsDashboard.fromJson(Object? data) {
    final json = requireMap(data, 'reports dashboard');
    final outstanding = requireMap(json['outstanding'], 'outstanding');
    return ReportsDashboard(
      from: requireString(json, 'from'),
      to: requireString(json, 'to'),
      wingCode: optionalString(json, 'wingCode'),
      financial: ReportsDashboardFinancial.fromJson(
        requireMap(json['financial'], 'financial'),
      ),
      collections: ReportsDashboardCollections.fromJson(
        requireMap(json['collections'], 'collections'),
      ),
      outstandingTotals: ReportsDashboardOutstandingTotals.fromJson(
        requireMap(outstanding['totals'], 'totals'),
      ),
      topFlats:
          requireMapList(outstanding, 'topFlats').map(OutstandingFlat.fromJson).toList(),
      complaints: ReportsDashboardComplaints.fromJson(
        requireMap(json['complaints'], 'complaints'),
      ),
    );
  }
}

/// Builds a download filename from export type and report date range.
String reportCsvFilename({
  required String type,
  String? from,
  String? to,
}) {
  final safeType = type.trim().isEmpty ? 'report' : type.trim();
  String slice(String? iso) {
    if (iso == null || iso.isEmpty) return 'all';
    return iso.length >= 10 ? iso.substring(0, 10) : iso;
  }

  final fromPart = slice(from);
  final toPart = slice(to);
  if (fromPart == 'all' && toPart == 'all') {
    return '$safeType-report.csv';
  }
  if (fromPart == toPart) {
    return '$safeType-report-$fromPart.csv';
  }
  return '$safeType-report-$fromPart-to-$toPart.csv';
}

class ReportQuery {
  const ReportQuery({
    this.from,
    this.to,
    this.wingCode,
    this.wingId,
    this.flatId,
    this.paymentMethod,
    this.paymentStatus,
    this.page,
    this.limit,
  });

  final String? from;
  final String? to;
  final String? wingCode;
  final String? wingId;
  final String? flatId;
  final String? paymentMethod;
  final String? paymentStatus;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'from': from,
        'to': to,
        'wingCode': wingCode,
        'wingId': wingId,
        'flatId': flatId,
        'paymentMethod': paymentMethod,
        'paymentStatus': paymentStatus,
        'page': page,
        'limit': limit,
      };
}

const reportExportTypes = [
  'financial',
  'collections',
  'outstanding',
  'payments',
  'complaints',
];
