import '../http/json_read.dart';

const kStaffCategories = [
  'SECURITY',
  'HOUSEKEEPING',
  'MAINTENANCE',
  'ELECTRICIAN',
  'PLUMBER',
  'GARDENER',
  'LIFT_OPERATOR',
  'OTHER',
];

const kEmploymentTypes = ['PERMANENT', 'CONTRACT', 'TEMPORARY'];
const kEmploymentStatuses = ['ACTIVE', 'INACTIVE', 'TERMINATED'];
const kAttendanceStatuses = ['PRESENT', 'ABSENT', 'HALF_DAY', 'ON_LEAVE'];
const kShiftStatuses = ['SCHEDULED', 'CANCELLED', 'COMPLETED'];

String staffCategoryLabel(String v) {
  switch (v) {
    case 'SECURITY':
      return 'Security';
    case 'HOUSEKEEPING':
      return 'Housekeeping';
    case 'MAINTENANCE':
      return 'Maintenance';
    case 'ELECTRICIAN':
      return 'Electrician';
    case 'PLUMBER':
      return 'Plumber';
    case 'GARDENER':
      return 'Gardener';
    case 'LIFT_OPERATOR':
      return 'Lift operator';
    case 'OTHER':
      return 'Other';
    default:
      return v;
  }
}

String employmentStatusLabel(String v) {
  switch (v) {
    case 'ACTIVE':
      return 'Active';
    case 'INACTIVE':
      return 'Inactive';
    case 'TERMINATED':
      return 'Terminated';
    default:
      return v;
  }
}

String attendanceStatusLabel(String v) {
  switch (v) {
    case 'PRESENT':
      return 'Present';
    case 'ABSENT':
      return 'Absent';
    case 'HALF_DAY':
      return 'Half day';
    case 'ON_LEAVE':
      return 'On leave';
    default:
      return v;
  }
}

class StaffMember {
  const StaffMember({
    required this.id,
    required this.societyId,
    required this.fullName,
    required this.phone,
    required this.category,
    required this.employmentType,
    required this.joiningDate,
    required this.employmentStatus,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.notes,
    this.linkedUserId,
    this.deactivatedAt,
    this.terminatedAt,
    this.statusReason,
  });

  final String id;
  final String societyId;
  final String fullName;
  final String phone;
  final String? email;
  final String category;
  final String employmentType;
  final String joiningDate;
  final String employmentStatus;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? notes;
  final String? linkedUserId;
  final String createdBy;
  final String? deactivatedAt;
  final String? terminatedAt;
  final String? statusReason;
  final String createdAt;
  final String updatedAt;

  factory StaffMember.fromJson(Object? data) {
    final json = requireMap(data, 'staff');
    return StaffMember(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      fullName: requireString(json, 'fullName'),
      phone: requireString(json, 'phone'),
      email: optionalString(json, 'email'),
      category: requireString(json, 'category'),
      employmentType: requireString(json, 'employmentType'),
      joiningDate: requireString(json, 'joiningDate'),
      employmentStatus: requireString(json, 'employmentStatus'),
      address: optionalString(json, 'address'),
      emergencyContactName: optionalString(json, 'emergencyContactName'),
      emergencyContactPhone: optionalString(json, 'emergencyContactPhone'),
      notes: optionalString(json, 'notes'),
      linkedUserId: optionalString(json, 'linkedUserId'),
      createdBy: requireString(json, 'createdBy'),
      deactivatedAt: optionalString(json, 'deactivatedAt'),
      terminatedAt: optionalString(json, 'terminatedAt'),
      statusReason: optionalString(json, 'statusReason'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class CreateStaffRequest {
  const CreateStaffRequest({
    required this.fullName,
    required this.phone,
    required this.category,
    required this.employmentType,
    required this.joiningDate,
    this.email,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.notes,
    this.linkedUserId,
  });

  final String fullName;
  final String phone;
  final String? email;
  final String category;
  final String employmentType;
  final String joiningDate;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? notes;
  final String? linkedUserId;

  Map<String, Object?> toJson() => omitNulls({
        'fullName': fullName,
        'phone': phone,
        'email': email,
        'category': category,
        'employmentType': employmentType,
        'joiningDate': joiningDate,
        'address': address,
        'emergencyContactName': emergencyContactName,
        'emergencyContactPhone': emergencyContactPhone,
        'notes': notes,
        'linkedUserId': linkedUserId,
      });
}

class UpdateStaffRequest {
  const UpdateStaffRequest({
    this.fullName,
    this.phone,
    this.email,
    this.category,
    this.employmentType,
    this.address,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.notes,
    this.linkedUserId,
    this.clearLinkedUser = false,
  });

  final String? fullName;
  final String? phone;
  final String? email;
  final String? category;
  final String? employmentType;
  final String? address;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? notes;
  final String? linkedUserId;
  final bool clearLinkedUser;

  Map<String, Object?> toJson() {
    final map = omitNulls({
      'fullName': fullName,
      'phone': phone,
      'email': email,
      'category': category,
      'employmentType': employmentType,
      'address': address,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'notes': notes,
    });
    if (clearLinkedUser) {
      map['linkedUserId'] = null;
    } else if (linkedUserId != null) {
      map['linkedUserId'] = linkedUserId;
    }
    return map;
  }
}

class ListStaffQuery {
  const ListStaffQuery({
    this.category,
    this.employmentType,
    this.employmentStatus,
    this.joiningFrom,
    this.joiningTo,
    this.page,
    this.limit,
  });

  final String? category;
  final String? employmentType;
  final String? employmentStatus;
  final String? joiningFrom;
  final String? joiningTo;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'category': category,
        'employmentType': employmentType,
        'employmentStatus': employmentStatus,
        'joiningFrom': joiningFrom,
        'joiningTo': joiningTo,
        'page': page,
        'limit': limit,
      };
}

class MarkAttendanceRequest {
  const MarkAttendanceRequest({
    required this.staffId,
    required this.status,
    this.localDate,
    this.checkInAt,
    this.notes,
  });

  final String staffId;
  final String? localDate;
  final String status;
  final String? checkInAt;
  final String? notes;

  Map<String, Object?> toJson() => omitNulls({
        'staffId': staffId,
        'localDate': localDate,
        'status': status,
        'checkInAt': checkInAt,
        'notes': notes,
      });
}

class CorrectAttendanceRequest {
  const CorrectAttendanceRequest({
    required this.reason,
    this.status,
    this.checkInAt,
    this.checkOutAt,
    this.clearCheckIn = false,
    this.clearCheckOut = false,
    this.notes,
  });

  final String? status;
  final String? checkInAt;
  final String? checkOutAt;
  final bool clearCheckIn;
  final bool clearCheckOut;
  final String? notes;
  final String reason;

  Map<String, Object?> toJson() {
    final map = omitNulls({
      'status': status,
      'notes': notes,
      'reason': reason,
    });
    if (clearCheckIn) {
      map['checkInAt'] = null;
    } else if (checkInAt != null) {
      map['checkInAt'] = checkInAt;
    }
    if (clearCheckOut) {
      map['checkOutAt'] = null;
    } else if (checkOutAt != null) {
      map['checkOutAt'] = checkOutAt;
    }
    return map;
  }
}

class CreateShiftRequest {
  const CreateShiftRequest({
    required this.staffId,
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    this.dutyLocation,
    this.notes,
  });

  final String staffId;
  final String shiftDate;
  final String startTime;
  final String endTime;
  final String? dutyLocation;
  final String? notes;

  Map<String, Object?> toJson() => omitNulls({
        'staffId': staffId,
        'shiftDate': shiftDate,
        'startTime': startTime,
        'endTime': endTime,
        'dutyLocation': dutyLocation,
        'notes': notes,
      });
}

class UpdateShiftRequest {
  const UpdateShiftRequest({
    this.shiftDate,
    this.startTime,
    this.endTime,
    this.dutyLocation,
    this.notes,
  });

  final String? shiftDate;
  final String? startTime;
  final String? endTime;
  final String? dutyLocation;
  final String? notes;

  Map<String, Object?> toJson() => omitNulls({
        'shiftDate': shiftDate,
        'startTime': startTime,
        'endTime': endTime,
        'dutyLocation': dutyLocation,
        'notes': notes,
      });
}

class StaffShiftEventPayload {
  const StaffShiftEventPayload({
    required this.shiftId,
    required this.societyId,
    required this.staffId,
    required this.linkedUserId,
    required this.shiftDate,
    required this.startAt,
    required this.endAt,
    this.dutyLocation,
  });

  final String shiftId;
  final String societyId;
  final String staffId;
  final String linkedUserId;
  final String shiftDate;
  final String startAt;
  final String endAt;
  final String? dutyLocation;

  factory StaffShiftEventPayload.fromJson(Object? data) {
    final json = requireMap(data, 'staff shift event');
    return StaffShiftEventPayload(
      shiftId: requireString(json, 'shiftId'),
      societyId: requireString(json, 'societyId'),
      staffId: requireString(json, 'staffId'),
      linkedUserId: requireString(json, 'linkedUserId'),
      shiftDate: requireString(json, 'shiftDate'),
      startAt: requireString(json, 'startAt'),
      endAt: requireString(json, 'endAt'),
      dutyLocation: optionalString(json, 'dutyLocation'),
    );
  }
}

class AttendanceCorrection {
  const AttendanceCorrection({
    required this.correctedByUserId,
    required this.correctedAt,
    required this.reason,
    this.previous,
  });

  final String correctedByUserId;
  final String correctedAt;
  final Map<String, Object?>? previous;
  final String reason;

  factory AttendanceCorrection.fromJson(JsonMap json) {
    final prev = json['previous'];
    return AttendanceCorrection(
      correctedByUserId: requireString(json, 'correctedByUserId'),
      correctedAt: requireString(json, 'correctedAt'),
      previous: prev is Map
          ? prev.map((k, v) => MapEntry(k.toString(), v))
          : null,
      reason: requireString(json, 'reason'),
    );
  }
}

class StaffAttendance {
  const StaffAttendance({
    required this.id,
    required this.societyId,
    required this.staffId,
    required this.localDate,
    required this.status,
    required this.recordedByUserId,
    required this.correctionHistory,
    required this.createdAt,
    required this.updatedAt,
    this.checkInAt,
    this.checkOutAt,
    this.notes,
  });

  final String id;
  final String societyId;
  final String staffId;
  final String localDate;
  final String? checkInAt;
  final String? checkOutAt;
  final String status;
  final String recordedByUserId;
  final String? notes;
  final List<AttendanceCorrection> correctionHistory;
  final String createdAt;
  final String updatedAt;

  factory StaffAttendance.fromJson(Object? data) {
    final json = requireMap(data, 'attendance');
    final history = json['correctionHistory'];
    return StaffAttendance(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      staffId: requireString(json, 'staffId'),
      localDate: requireString(json, 'localDate'),
      checkInAt: optionalString(json, 'checkInAt'),
      checkOutAt: optionalString(json, 'checkOutAt'),
      status: requireString(json, 'status'),
      recordedByUserId: requireString(json, 'recordedByUserId'),
      notes: optionalString(json, 'notes'),
      correctionHistory: history is List
          ? history
              .map(
                (item) => AttendanceCorrection.fromJson(
                  requireMap(item, 'correction'),
                ),
              )
              .toList()
          : const [],
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class ListAttendanceQuery {
  const ListAttendanceQuery({
    this.staffId,
    this.localDate,
    this.from,
    this.to,
    this.status,
    this.category,
    this.page,
    this.limit,
  });

  final String? staffId;
  final String? localDate;
  final String? from;
  final String? to;
  final String? status;
  final String? category;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'staffId': staffId,
        'localDate': localDate,
        'from': from,
        'to': to,
        'status': status,
        'category': category,
        'page': page,
        'limit': limit,
      };
}

class AttendanceSummary {
  const AttendanceSummary({
    required this.total,
    required this.byStatus,
  });

  final int total;
  final Map<String, int> byStatus;

  factory AttendanceSummary.fromJson(Object? data) {
    final json = requireMap(data, 'attendance summary');
    final raw = json['byStatus'];
    final byStatus = <String, int>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.key is String && e.value is num) {
          byStatus[e.key as String] = (e.value as num).toInt();
        }
      }
    }
    return AttendanceSummary(
      total: requireInt(json, 'total'),
      byStatus: byStatus,
    );
  }
}

class StaffShift {
  const StaffShift({
    required this.id,
    required this.societyId,
    required this.staffId,
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.dutyLocation,
    this.notes,
    this.cancelledAt,
    this.cancelReason,
  });

  final String id;
  final String societyId;
  final String staffId;
  final String shiftDate;
  final String startTime;
  final String endTime;
  final String startAt;
  final String endAt;
  final String? dutyLocation;
  final String? notes;
  final String status;
  final String createdBy;
  final String? cancelledAt;
  final String? cancelReason;
  final String createdAt;
  final String updatedAt;

  bool get isOvernight {
    final start = DateTime.tryParse(startAt);
    final end = DateTime.tryParse(endAt);
    if (start == null || end == null) return false;
    return end.day != start.day || end.isBefore(start);
  }

  factory StaffShift.fromJson(Object? data) {
    final json = requireMap(data, 'shift');
    return StaffShift(
      id: requireString(json, 'id'),
      societyId: requireString(json, 'societyId'),
      staffId: requireString(json, 'staffId'),
      shiftDate: requireString(json, 'shiftDate'),
      startTime: requireString(json, 'startTime'),
      endTime: requireString(json, 'endTime'),
      startAt: requireString(json, 'startAt'),
      endAt: requireString(json, 'endAt'),
      dutyLocation: optionalString(json, 'dutyLocation'),
      notes: optionalString(json, 'notes'),
      status: requireString(json, 'status'),
      createdBy: requireString(json, 'createdBy'),
      cancelledAt: optionalString(json, 'cancelledAt'),
      cancelReason: optionalString(json, 'cancelReason'),
      createdAt: requireString(json, 'createdAt'),
      updatedAt: requireString(json, 'updatedAt'),
    );
  }
}

class ListShiftsQuery {
  const ListShiftsQuery({
    this.staffId,
    this.from,
    this.to,
    this.status,
    this.page,
    this.limit,
  });

  final String? staffId;
  final String? from;
  final String? to;
  final String? status;
  final int? page;
  final int? limit;

  Map<String, Object?> toQuery() => {
        'staffId': staffId,
        'from': from,
        'to': to,
        'status': status,
        'page': page,
        'limit': limit,
      };
}

const kStaffSocketEvents = ['staff:shift_assigned'];
