import '../http/json_read.dart';

const kFacilityCategories = [
  'CLUBHOUSE',
  'GYM',
  'SWIMMING_POOL',
  'COMMUNITY_HALL',
  'GARDEN',
  'SPORTS_COURT',
  'INDOOR_GAMES',
  'OTHER',
];

const kWeekdays = [
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY',
];

const kFacilityBookingStatuses = [
  'PENDING',
  'CONFIRMED',
  'REJECTED',
  'CANCELLED',
  'COMPLETED',
];

String facilityCategoryLabel(String v) {
  switch (v) {
    case 'CLUBHOUSE':
      return 'Clubhouse';
    case 'GYM':
      return 'Gym';
    case 'SWIMMING_POOL':
      return 'Swimming pool';
    case 'COMMUNITY_HALL':
      return 'Community hall';
    case 'GARDEN':
      return 'Garden';
    case 'SPORTS_COURT':
      return 'Sports court';
    case 'INDOOR_GAMES':
      return 'Indoor games';
    case 'OTHER':
      return 'Other';
    default:
      return v;
  }
}

String weekdayLabel(String v) {
  switch (v) {
    case 'MONDAY':
      return 'Mon';
    case 'TUESDAY':
      return 'Tue';
    case 'WEDNESDAY':
      return 'Wed';
    case 'THURSDAY':
      return 'Thu';
    case 'FRIDAY':
      return 'Fri';
    case 'SATURDAY':
      return 'Sat';
    case 'SUNDAY':
      return 'Sun';
    default:
      return v;
  }
}

String facilityBookingStatusLabel(String v) {
  switch (v) {
    case 'PENDING':
      return 'Pending';
    case 'CONFIRMED':
      return 'Confirmed';
    case 'REJECTED':
      return 'Rejected';
    case 'CANCELLED':
      return 'Cancelled';
    case 'COMPLETED':
      return 'Completed';
    default:
      return v;
  }
}

class Facility {
  const Facility({
    required this.id,
    required this.societyId,
    required this.name,
    required this.category,
    required this.capacity,
    required this.bookingRequired,
    required this.requiresApproval,
    required this.maxBookingDurationMinutes,
    required this.openingTime,
    required this.closingTime,
    required this.availableDays,
    required this.isActive,
    required this.bookingFeePaise,
    required this.feePaymentRequired,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.location,
    this.createdBy,
    this.deactivatedAt,
  });

  final String id;
  final String societyId;
  final String name;
  final String? description;
  final String category;
  final String? location;
  final int capacity;
  final bool bookingRequired;
  final bool requiresApproval;
  final int maxBookingDurationMinutes;
  final String openingTime;
  final String closingTime;
  final List<String> availableDays;
  final bool isActive;
  final int bookingFeePaise;
  final bool feePaymentRequired;
  final String? createdBy;
  final String? deactivatedAt;
  final String createdAt;
  final String updatedAt;

  factory Facility.fromJson(Object? data) {
    final json = requireMap(data, 'facility');
    return Facility(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      name: requireString(json, 'name'),
      description: optionalString(json, 'description'),
      category: requireString(json, 'category'),
      location: optionalString(json, 'location'),
      capacity: requireInt(json, 'capacity'),
      bookingRequired: requireBool(json, 'bookingRequired'),
      requiresApproval: requireBool(json, 'requiresApproval'),
      maxBookingDurationMinutes: requireInt(json, 'maxBookingDurationMinutes'),
      openingTime: requireString(json, 'openingTime'),
      closingTime: requireString(json, 'closingTime'),
      availableDays: requireStringList(json, 'availableDays'),
      isActive: requireBool(json, 'isActive'),
      bookingFeePaise: requireInt(json, 'bookingFeePaise'),
      feePaymentRequired: requireBool(json, 'feePaymentRequired'),
      createdBy: optionalString(json, 'createdBy'),
      deactivatedAt: optionalString(json, 'deactivatedAt'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class CreateFacilityRequest {
  const CreateFacilityRequest({
    required this.name,
    required this.category,
    required this.capacity,
    required this.maxBookingDurationMinutes,
    required this.openingTime,
    required this.closingTime,
    required this.availableDays,
    this.description,
    this.location,
    this.bookingRequired,
    this.requiresApproval,
    this.bookingFeePaise,
  });

  final String name;
  final String? description;
  final String category;
  final String? location;
  final int capacity;
  final bool? bookingRequired;
  final bool? requiresApproval;
  final int maxBookingDurationMinutes;
  final String openingTime;
  final String closingTime;
  final List<String> availableDays;
  final int? bookingFeePaise;

  Map<String, Object?> toJson() => omitNulls({
        'name': name,
        'description': description,
        'category': category,
        'location': location,
        'capacity': capacity,
        'bookingRequired': bookingRequired,
        'requiresApproval': requiresApproval,
        'maxBookingDurationMinutes': maxBookingDurationMinutes,
        'openingTime': openingTime,
        'closingTime': closingTime,
        'availableDays': availableDays,
        'bookingFeePaise': bookingFeePaise,
      });
}

class UpdateFacilityRequest {
  const UpdateFacilityRequest({
    this.name,
    this.description,
    this.category,
    this.location,
    this.capacity,
    this.bookingRequired,
    this.requiresApproval,
    this.maxBookingDurationMinutes,
    this.openingTime,
    this.closingTime,
    this.availableDays,
    this.bookingFeePaise,
  });

  final String? name;
  final String? description;
  final String? category;
  final String? location;
  final int? capacity;
  final bool? bookingRequired;
  final bool? requiresApproval;
  final int? maxBookingDurationMinutes;
  final String? openingTime;
  final String? closingTime;
  final List<String>? availableDays;
  final int? bookingFeePaise;

  Map<String, Object?> toJson() => omitNulls({
        'name': name,
        'description': description,
        'category': category,
        'location': location,
        'capacity': capacity,
        'bookingRequired': bookingRequired,
        'requiresApproval': requiresApproval,
        'maxBookingDurationMinutes': maxBookingDurationMinutes,
        'openingTime': openingTime,
        'closingTime': closingTime,
        'availableDays': availableDays,
        'bookingFeePaise': bookingFeePaise,
      });
}

class ListFacilitiesQuery {
  const ListFacilitiesQuery({
    this.isActive,
    this.category,
    this.page,
    this.limit,
  });

  final bool? isActive;
  final String? category;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'isActive': isActive == null ? null : (isActive! ? 'true' : 'false'),
        'category': category,
        'page': page,
        'limit': limit,
      };
}

class ConfirmedSlot {
  const ConfirmedSlot({
    required this.startAt,
    required this.endAt,
    required this.startTime,
    required this.endTime,
  });

  final String startAt;
  final String endAt;
  final String startTime;
  final String endTime;

  factory ConfirmedSlot.fromJson(JsonMap json) {
    return ConfirmedSlot(
      startAt: requireString(json, 'startAt'),
      endAt: requireString(json, 'endAt'),
      startTime: requireString(json, 'startTime'),
      endTime: requireString(json, 'endTime'),
    );
  }
}

class FacilityAvailabilityPendingPolicy {
  const FacilityAvailabilityPendingPolicy({
    required this.requiresApproval,
    required this.pendingTtlMs,
    required this.pendingDoesNotConsumeCapacity,
    required this.onlyConfirmedCountsTowardCapacity,
  });

  final bool requiresApproval;
  final int pendingTtlMs;
  final bool pendingDoesNotConsumeCapacity;
  final bool onlyConfirmedCountsTowardCapacity;

  factory FacilityAvailabilityPendingPolicy.fromJson(JsonMap json) {
    return FacilityAvailabilityPendingPolicy(
      requiresApproval: requireBool(json, 'requiresApproval'),
      pendingTtlMs: requireInt(json, 'pendingTtlMs'),
      pendingDoesNotConsumeCapacity:
          requireBool(json, 'pendingDoesNotConsumeCapacity'),
      onlyConfirmedCountsTowardCapacity:
          requireBool(json, 'onlyConfirmedCountsTowardCapacity'),
    );
  }
}

class FacilityAvailability {
  const FacilityAvailability({
    required this.facilityId,
    required this.bookingDate,
    required this.capacity,
    required this.openingTime,
    required this.closingTime,
    required this.confirmedCount,
    required this.remainingCapacityHint,
    required this.confirmedSlots,
    required this.pendingPolicy,
  });

  final String facilityId;
  final String bookingDate;
  final int capacity;
  final String openingTime;
  final String closingTime;
  final int confirmedCount;
  final int remainingCapacityHint;
  final List<ConfirmedSlot> confirmedSlots;
  final FacilityAvailabilityPendingPolicy pendingPolicy;

  factory FacilityAvailability.fromJson(Object? data) {
    final json = requireMap(data, 'facility availability');
    return FacilityAvailability(
      facilityId: requireString(json, 'facilityId'),
      bookingDate: requireString(json, 'bookingDate'),
      capacity: requireInt(json, 'capacity'),
      openingTime: requireString(json, 'openingTime'),
      closingTime: requireString(json, 'closingTime'),
      confirmedCount: requireInt(json, 'confirmedCount'),
      remainingCapacityHint: requireInt(json, 'remainingCapacityHint'),
      confirmedSlots: requireMapList(json, 'confirmedSlots')
          .map(ConfirmedSlot.fromJson)
          .toList(),
      pendingPolicy: FacilityAvailabilityPendingPolicy.fromJson(
        requireMap(json['pendingPolicy'], 'pendingPolicy'),
      ),
    );
  }
}

class FacilityBooking {
  const FacilityBooking({
    required this.id,
    required this.societyId,
    required this.facilityId,
    required this.flatId,
    required this.bookedByUserId,
    required this.bookingDate,
    required this.startTime,
    required this.endTime,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.feePaiseSnapshot,
    required this.feePaid,
    required this.feePaymentRequired,
    required this.createdAt,
    required this.updatedAt,
    this.paymentReference,
    this.adminNotes,
    this.rejectionReason,
    this.cancellationReason,
    this.expiresAt,
  });

  final String id;
  final String societyId;
  final String facilityId;
  final String flatId;
  final String bookedByUserId;
  final String bookingDate;
  final String startTime;
  final String endTime;
  final String startAt;
  final String endAt;
  final String status;
  final int feePaiseSnapshot;
  final bool feePaid;
  final bool feePaymentRequired;
  final String? paymentReference;
  final String? adminNotes;
  final String? rejectionReason;
  final String? cancellationReason;
  final String? expiresAt;
  final String createdAt;
  final String updatedAt;

  bool get isPendingExpired {
    if (status != 'PENDING' || expiresAt == null) return false;
    final exp = DateTime.tryParse(expiresAt!);
    if (exp == null) return false;
    return !exp.isAfter(DateTime.now().toUtc());
  }

  factory FacilityBooking.fromJson(Object? data) {
    final json = requireMap(data, 'facility booking');
    return FacilityBooking(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      facilityId: requireString(json, 'facilityId'),
      flatId: requireString(json, 'flatId'),
      bookedByUserId: requireString(json, 'bookedByUserId'),
      bookingDate: requireString(json, 'bookingDate'),
      startTime: requireString(json, 'startTime'),
      endTime: requireString(json, 'endTime'),
      startAt: requireString(json, 'startAt'),
      endAt: requireString(json, 'endAt'),
      status: requireString(json, 'status'),
      feePaiseSnapshot: requireInt(json, 'feePaiseSnapshot'),
      feePaid: requireBool(json, 'feePaid'),
      feePaymentRequired: requireBool(json, 'feePaymentRequired'),
      paymentReference: optionalString(json, 'paymentReference'),
      adminNotes: optionalString(json, 'adminNotes'),
      rejectionReason: optionalString(json, 'rejectionReason'),
      cancellationReason: optionalString(json, 'cancellationReason'),
      expiresAt: optionalString(json, 'expiresAt'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class CreateFacilityBookingRequest {
  const CreateFacilityBookingRequest({
    required this.flatId,
    required this.bookingDate,
    required this.startTime,
    required this.endTime,
  });

  final String flatId;
  final String bookingDate;
  final String startTime;
  final String endTime;

  Map<String, Object?> toJson() => {
        'flatId': flatId,
        'bookingDate': bookingDate,
        'startTime': startTime,
        'endTime': endTime,
      };
}

class ListFacilityBookingsQuery {
  const ListFacilityBookingsQuery({
    this.facilityId,
    this.flatId,
    this.status,
    this.from,
    this.to,
    this.page,
    this.limit,
  });

  final String? facilityId;
  final String? flatId;
  final String? status;
  final String? from;
  final String? to;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'facilityId': facilityId,
        'flatId': flatId,
        'status': status,
        'from': from,
        'to': to,
        'page': page,
        'limit': limit,
      };
}

class FacilityBookingEventPayload {
  const FacilityBookingEventPayload({
    required this.bookingId,
    required this.societyId,
    required this.facilityId,
    required this.flatId,
    required this.bookedByUserId,
    required this.status,
    required this.bookingDate,
    required this.startAt,
    required this.endAt,
    required this.feePaiseSnapshot,
    required this.feePaid,
  });

  final String bookingId;
  final String societyId;
  final String facilityId;
  final String flatId;
  final String bookedByUserId;
  final String status;
  final String bookingDate;
  final String startAt;
  final String endAt;
  final int feePaiseSnapshot;
  final bool feePaid;

  factory FacilityBookingEventPayload.fromJson(Object? data) {
    final json = requireMap(data, 'facility booking event');
    return FacilityBookingEventPayload(
      bookingId: requireString(json, 'bookingId'),
      societyId: requireString(json, 'societyId'),
      facilityId: requireString(json, 'facilityId'),
      flatId: requireString(json, 'flatId'),
      bookedByUserId: requireString(json, 'bookedByUserId'),
      status: requireString(json, 'status'),
      bookingDate: requireString(json, 'bookingDate'),
      startAt: requireString(json, 'startAt'),
      endAt: requireString(json, 'endAt'),
      feePaiseSnapshot: requireInt(json, 'feePaiseSnapshot'),
      feePaid: requireBool(json, 'feePaid'),
    );
  }
}

const kFacilitySocketEvents = [
  'facility:booking_approved',
  'facility:booking_rejected',
  'facility:booking_cancelled',
];
