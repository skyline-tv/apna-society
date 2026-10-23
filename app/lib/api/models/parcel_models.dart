import '../http/json_read.dart';
import 'flat_label.dart';

const kParcelStatuses = [
  'AWAITING_HANDOVER',
  'RECEIVED_BY_GUARD',
  'DELIVERED_TO_RESIDENT',
  'COLLECTED_BY_RESIDENT',
  'CANCELLED',
];

String parcelStatusLabel(String status) {
  switch (status) {
    case 'AWAITING_HANDOVER':
      return 'Awaiting handover';
    case 'RECEIVED_BY_GUARD':
      return 'Received by guard';
    case 'DELIVERED_TO_RESIDENT':
      return 'Delivered to resident';
    case 'COLLECTED_BY_RESIDENT':
      return 'Collected by resident';
    case 'CANCELLED':
      return 'Cancelled';
    default:
      return status;
  }
}

class ParcelHandover {
  const ParcelHandover({
    required this.id,
    required this.societyId,
    required this.flatId,
    required this.recipientUserId,
    required this.courierName,
    required this.requestedByGuardId,
    required this.authorizedByUserId,
    required this.status,
    required this.requestedAt,
    required this.authorizedAt,
    required this.flatNumberSnapshot,
    required this.wingCodeSnapshot,
    required this.createdAt,
    required this.updatedAt,
    this.visitorLogId,
    this.courierPhone,
    this.visitorType,
    this.purpose,
    this.receivedByGuardId,
    this.receivedAt,
    this.deliveredAt,
    this.collectedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.notes,
  });

  final String id;
  final String societyId;
  final String flatId;
  final String? visitorLogId;
  final String recipientUserId;
  final String courierName;
  final String? courierPhone;
  final String? visitorType;
  final String? purpose;
  final String requestedByGuardId;
  final String authorizedByUserId;
  final String? receivedByGuardId;
  final String status;
  final String requestedAt;
  final String authorizedAt;
  final String? receivedAt;
  final String? deliveredAt;
  final String? collectedAt;
  final String? cancelledAt;
  final String? cancellationReason;
  final String? notes;
  final String flatNumberSnapshot;
  final String wingCodeSnapshot;
  final String createdAt;
  final String updatedAt;

  String get flatLabel => formatFlatLabel(wingCodeSnapshot, flatNumberSnapshot);

  factory ParcelHandover.fromJson(Object? data) {
    final json = requireMap(data, 'parcel');
    return ParcelHandover(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      flatId: requireString(json, 'flatId'),
      visitorLogId: optionalString(json, 'visitorLogId'),
      recipientUserId: requireString(json, 'recipientUserId'),
      courierName: requireString(json, 'courierName'),
      courierPhone: optionalString(json, 'courierPhone'),
      visitorType: optionalString(json, 'visitorType'),
      purpose: optionalString(json, 'purpose'),
      requestedByGuardId: requireString(json, 'requestedByGuardId'),
      authorizedByUserId: requireString(json, 'authorizedByUserId'),
      receivedByGuardId: optionalString(json, 'receivedByGuardId'),
      status: requireString(json, 'status'),
      requestedAt: requireString(json, 'requestedAt'),
      authorizedAt: requireString(json, 'authorizedAt'),
      receivedAt: optionalString(json, 'receivedAt'),
      deliveredAt: optionalString(json, 'deliveredAt'),
      collectedAt: optionalString(json, 'collectedAt'),
      cancelledAt: optionalString(json, 'cancelledAt'),
      cancellationReason: optionalString(json, 'cancellationReason'),
      notes: optionalString(json, 'notes'),
      flatNumberSnapshot: requireString(json, 'flatNumberSnapshot'),
      wingCodeSnapshot: requireString(json, 'wingCodeSnapshot'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class ParcelAuthorizationResult {
  const ParcelAuthorizationResult({required this.visitor, required this.parcel});

  final VisitorLike visitor;
  final ParcelHandover parcel;

  factory ParcelAuthorizationResult.fromJson(Object? data) {
    final json = requireMap(data, 'parcel authorization');
    return ParcelAuthorizationResult(
      visitor: VisitorLike.fromJson(json['visitor']),
      parcel: ParcelHandover.fromJson(json['parcel']),
    );
  }
}

/// Minimal visitor fields returned with parcel authorization.
class VisitorLike {
  const VisitorLike({
    required this.id,
    required this.approvalStatus,
    this.resolution,
    this.entryStatus,
  });

  final String id;
  final String approvalStatus;
  final String? resolution;
  final String? entryStatus;

  factory VisitorLike.fromJson(Object? data) {
    final json = requireMap(data, 'visitor');
    return VisitorLike(
      id: requireString(json, 'id'),
      approvalStatus: requireString(json, 'approvalStatus'),
      resolution: optionalString(json, 'resolution'),
      entryStatus: optionalString(json, 'entryStatus'),
    );
  }
}
