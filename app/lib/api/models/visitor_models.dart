import '../http/json_read.dart';
import 'flat_label.dart';

/// Backend `VISITOR_TYPES`.
const kVisitorTypes = [
  'GUEST',
  'DELIVERY',
  'CAB',
  'COURIER',
  'SERVICE_PROVIDER',
  'OTHER',
];

/// Backend `APPROVAL_STATUSES`.
const kApprovalStatuses = [
  'PENDING',
  'APPROVED',
  'REJECTED',
  'EXPIRED',
  'CANCELLED',
];

/// Backend `ENTRY_STATUSES`.
const kEntryStatuses = ['NOT_ENTERED', 'ENTERED', 'EXITED'];

String visitorTypeLabel(String type) {
  switch (type) {
    case 'GUEST':
      return 'Guest';
    case 'DELIVERY':
      return 'Delivery';
    case 'CAB':
      return 'Cab';
    case 'COURIER':
      return 'Courier';
    case 'SERVICE_PROVIDER':
      return 'Service provider';
    case 'OTHER':
      return 'Other';
    default:
      return type;
  }
}

String approvalStatusLabel(String status) {
  switch (status) {
    case 'PENDING':
      return 'Pending approval';
    case 'APPROVED':
      return 'Approved';
    case 'REJECTED':
      return 'Rejected';
    case 'EXPIRED':
      return 'Expired';
    case 'CANCELLED':
      return 'Cancelled';
    default:
      return status;
  }
}

String entryStatusLabel(String status) {
  switch (status) {
    case 'NOT_ENTERED':
      return 'Not entered';
    case 'ENTERED':
      return 'Inside';
    case 'EXITED':
      return 'Exited';
    default:
      return status;
  }
}

class Visitor {
  const Visitor({
    required this.id,
    required this.societyId,
    required this.flatId,
    required this.visitorName,
    required this.visitorPhone,
    required this.visitorType,
    required this.purpose,
    required this.numberOfVisitors,
    required this.requestedByGuardId,
    required this.assignedResidentUserId,
    required this.assignedResidentRole,
    required this.approvalStatus,
    required this.entryStatus,
    required this.hasActiveOtp,
    required this.flatNumberSnapshot,
    required this.wingCodeSnapshot,
    required this.createdAt,
    required this.updatedAt,
    this.vehicleNumber,
    this.otpExpiresAt,
    this.otpAttempts,
    this.otpVerified = false,
    this.residentName,
    this.societyName,
    this.approvedAt,
    this.rejectedAt,
    this.entryAt,
    this.exitAt,
    this.checkedInBy,
    this.checkedOutBy,
    this.rejectionReason,
    this.notes,
    this.expiredAt,
  });

  final String id;
  final String societyId;
  final String flatId;
  final String visitorName;
  final String visitorPhone;
  final String visitorType;
  final String purpose;
  final String? vehicleNumber;
  final int numberOfVisitors;
  final String requestedByGuardId;
  final String assignedResidentUserId;
  final String assignedResidentRole;
  final String approvalStatus;
  final String entryStatus;
  final String? otpExpiresAt;
  final bool hasActiveOtp;
  final bool otpVerified;
  final int? otpAttempts;
  final String? residentName;
  final String? societyName;
  final String? approvedAt;
  final String? rejectedAt;
  final String? entryAt;
  final String? exitAt;
  final String? checkedInBy;
  final String? checkedOutBy;
  final String? rejectionReason;
  final String? notes;
  final String flatNumberSnapshot;
  final String wingCodeSnapshot;
  String get flatLabel =>
      formatFlatLabel(wingCodeSnapshot, flatNumberSnapshot);
  final String? expiredAt;
  final String createdAt;
  final String updatedAt;

  factory Visitor.fromJson(Object? data) {
    final json = requireMap(data, 'visitor');
    return Visitor(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      flatId: requireString(json, 'flatId'),
      visitorName: requireString(json, 'visitorName'),
      visitorPhone: requireString(json, 'visitorPhone'),
      visitorType: requireString(json, 'visitorType'),
      purpose: requireString(json, 'purpose'),
      vehicleNumber: optionalString(json, 'vehicleNumber'),
      numberOfVisitors: requireInt(json, 'numberOfVisitors'),
      requestedByGuardId: requireString(json, 'requestedByGuardId'),
      assignedResidentUserId:
          optionalString(json, 'assignedResidentUserId') ?? '',
      assignedResidentRole: optionalString(json, 'assignedResidentRole') ?? '',
      approvalStatus: requireString(json, 'approvalStatus'),
      entryStatus: requireString(json, 'entryStatus'),
      otpExpiresAt: optionalString(json, 'otpExpiresAt'),
      hasActiveOtp: requireBool(json, 'hasActiveOtp'),
      otpVerified: optionalBool(json, 'otpVerified') ?? false,
      otpAttempts: optionalInt(json, 'otpAttempts'),
      residentName: optionalString(json, 'residentName'),
      societyName: optionalString(json, 'societyName'),
      approvedAt: optionalString(json, 'approvedAt'),
      rejectedAt: optionalString(json, 'rejectedAt'),
      entryAt: optionalString(json, 'entryAt'),
      exitAt: optionalString(json, 'exitAt'),
      checkedInBy: optionalString(json, 'checkedInBy'),
      checkedOutBy: optionalString(json, 'checkedOutBy'),
      rejectionReason: optionalString(json, 'rejectionReason'),
      notes: optionalString(json, 'notes'),
      flatNumberSnapshot: requireString(json, 'flatNumberSnapshot'),
      wingCodeSnapshot: requireString(json, 'wingCodeSnapshot'),
      expiredAt: optionalString(json, 'expiredAt'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class GuardDashboard {
  const GuardDashboard({
    required this.currentlyInside,
    required this.pendingApprovals,
    required this.awaitingEntry,
    required this.enteredToday,
    required this.exitedToday,
    required this.recent,
  });

  final int currentlyInside;
  final int pendingApprovals;
  final int awaitingEntry;
  final int enteredToday;
  final int exitedToday;
  final List<Visitor> recent;

  factory GuardDashboard.fromJson(Object? data) {
    final json = requireMap(data, 'guard dashboard');
    return GuardDashboard(
      currentlyInside: requireInt(json, 'currentlyInside'),
      pendingApprovals: requireInt(json, 'pendingApprovals'),
      awaitingEntry: requireInt(json, 'awaitingEntry'),
      enteredToday: requireInt(json, 'enteredToday'),
      exitedToday: requireInt(json, 'exitedToday'),
      recent: requireMapList(json, 'recent').map(Visitor.fromJson).toList(),
    );
  }
}

class CreateVisitorRequest {
  const CreateVisitorRequest({
    required this.flatId,
    required this.visitorName,
    required this.visitorPhone,
    required this.visitorType,
    required this.purpose,
    this.visitorEmail,
    this.vehicleNumber,
    this.numberOfVisitors = 1,
    this.notes,
  });

  final String flatId;
  final String visitorName;
  final String visitorPhone;
  final String? visitorEmail;
  final String visitorType;
  final String purpose;
  final String? vehicleNumber;
  final int numberOfVisitors;
  final String? notes;

  Map<String, Object?> toJson() => {
        'flatId': flatId,
        'visitorName': visitorName,
        'visitorPhone': visitorPhone,
        'visitorEmail': visitorEmail,
        'visitorType': visitorType,
        'purpose': purpose,
        'vehicleNumber': vehicleNumber,
        'numberOfVisitors': numberOfVisitors,
        'notes': notes,
      };
}

class ListVisitorsQuery {
  const ListVisitorsQuery({
    this.approvalStatus,
    this.entryStatus,
    this.flatId,
    this.wingCode,
    this.visitorType,
    this.visitorPhone,
    this.visitorName,
    this.from,
    this.to,
    this.page,
    this.limit,
  });

  final String? approvalStatus;
  final String? entryStatus;
  final String? flatId;
  final String? wingCode;
  final String? visitorType;
  final String? visitorPhone;
  final String? visitorName;
  final String? from;
  final String? to;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'approvalStatus': approvalStatus,
        'entryStatus': entryStatus,
        'flatId': flatId,
        'wingCode': wingCode,
        'visitorType': visitorType,
        'visitorPhone': visitorPhone,
        'visitorName': visitorName,
        'from': from,
        'to': to,
        'page': page,
        'limit': limit,
      };
}

/// `GET /api/v1/admin/visitors/summary`
class AdminVisitorSummary {
  const AdminVisitorSummary({
    required this.total,
    required this.byApprovalStatus,
    required this.byEntryStatus,
  });

  final int total;
  final Map<String, int> byApprovalStatus;
  final Map<String, int> byEntryStatus;

  factory AdminVisitorSummary.fromJson(Object? data) {
    final json = requireMap(data, 'visitor summary');
    return AdminVisitorSummary(
      total: requireInt(json, 'total'),
      byApprovalStatus: _countMap(json['byApprovalStatus']),
      byEntryStatus: _countMap(json['byEntryStatus']),
    );
  }

  static Map<String, int> _countMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.key is String)
          e.key as String: e.value is num ? (e.value as num).toInt() : 0,
    };
  }
}

/// Socket.IO visitor event payload (OTP never included).
class VisitorEventPayload {
  const VisitorEventPayload({
    required this.visitorId,
    required this.societyId,
    required this.flatId,
    required this.flatNumberSnapshot,
    required this.wingCodeSnapshot,
    required this.visitorName,
    required this.visitorType,
    required this.approvalStatus,
    required this.entryStatus,
    this.assignedResidentUserId,
  });

  final String visitorId;
  final String societyId;
  final String flatId;
  final String flatNumberSnapshot;
  final String wingCodeSnapshot;
  final String visitorName;
  final String visitorType;
  final String approvalStatus;
  final String entryStatus;
  final String? assignedResidentUserId;

  factory VisitorEventPayload.fromJson(Object? data) {
    final json = requireMap(data, 'visitor event');
    return VisitorEventPayload(
      visitorId: requireString(json, 'visitorId'),
      societyId: requireString(json, 'societyId'),
      flatId: requireString(json, 'flatId'),
      flatNumberSnapshot: requireString(json, 'flatNumberSnapshot'),
      wingCodeSnapshot: requireString(json, 'wingCodeSnapshot'),
      visitorName: requireString(json, 'visitorName'),
      visitorType: requireString(json, 'visitorType'),
      approvalStatus: requireString(json, 'approvalStatus'),
      entryStatus: requireString(json, 'entryStatus'),
      assignedResidentUserId:
          optionalString(json, 'assignedResidentUserId') ?? '',
    );
  }
}

/// Known visitor Socket.IO event names from backend-v2.
const kVisitorSocketEvents = [
  'visitor:approval_requested',
  'visitor:approved',
  'visitor:rejected',
  'visitor:entered',
  'visitor:exited',
];
