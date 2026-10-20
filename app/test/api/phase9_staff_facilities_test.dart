import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/facility_models.dart';
import 'package:apna_society/api/models/staff_models.dart';
import 'package:apna_society/api/repositories/facility_repository.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:apna_society/api/repositories/staff_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(clearLiveRepositories);

  group('Staff DTO parsing', () {
    test('parses staff with optional linked user', () {
      final s = StaffMember.fromJson(_staff());
      expect(s.id, staffId);
      expect(s.employmentStatus, 'ACTIVE');
      expect(s.linkedUserId, isNull);
      expect(s.category, 'SECURITY');
    });

    test('parses linked guard user when provided', () {
      final s = StaffMember.fromJson(_staff(linkedUserId: linkedUserId));
      expect(s.linkedUserId, linkedUserId);
    });

    test('parses attendance with society localDate and corrections', () {
      final a = StaffAttendance.fromJson(_attendance(withCorrection: true));
      expect(a.localDate, '2026-10-20');
      expect(a.correctionHistory, hasLength(1));
      expect(a.correctionHistory.first.reason, 'Typo');
    });

    test('overnight shift display from startAt/endAt', () {
      final overnight = StaffShift.fromJson(_shift(
        startAt: '2026-10-20T18:30:00.000Z',
        endAt: '2026-10-21T02:30:00.000Z',
        startTime: '00:00',
        endTime: '08:00',
      ));
      expect(overnight.isOvernight, isTrue);

      final day = StaffShift.fromJson(_shift());
      expect(day.isOvernight, isFalse);
    });
  });

  group('Staff CRUD and deactivation', () {
    test('creates staff without inventing login role', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/admin/staff'), isTrue);
        expect(options.data['fullName'], 'Ravi Guard');
        expect(options.data.containsKey('role'), isFalse);
        return jsonBody(201, {'success': true, 'data': _staff()});
      });
      final repo = StaffRepository(_api(adapter).staff);
      final created = await repo.createStaff(
        const CreateStaffRequest(
          fullName: 'Ravi Guard',
          phone: '9876543210',
          category: 'SECURITY',
          employmentType: 'PERMANENT',
          joiningDate: '2026-01-01',
        ),
      );
      expect(created.employmentStatus, 'ACTIVE');
      expect(created.linkedUserId, isNull);
    });

    test('lists staff with pagination', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_staff()],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = StaffRepository(_api(adapter).staff);
      final page = await repo.listStaff();
      expect(page.items, hasLength(1));
    });

    test('deactivates staff', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/deactivate'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': _staff(status: 'INACTIVE'),
        });
      });
      final repo = StaffRepository(_api(adapter).staff);
      final updated = await repo.deactivateStaff(staffId, reason: 'Leave');
      expect(updated.employmentStatus, 'INACTIVE');
    });

    test('optional linked user on update clear', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.data.containsKey('linkedUserId'), isTrue);
        expect(options.data['linkedUserId'], isNull);
        return jsonBody(200, {'success': true, 'data': _staff()});
      });
      final repo = StaffRepository(_api(adapter).staff);
      final updated = await repo.updateStaff(
        staffId,
        const UpdateStaffRequest(clearLinkedUser: true),
      );
      expect(updated.linkedUserId, isNull);
    });
  });

  group('Attendance', () {
    test('marks attendance using server localDate when omitted', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.data.containsKey('localDate'), isFalse);
        expect(options.data['status'], 'PRESENT');
        return jsonBody(201, {
          'success': true,
          'data': _attendance(),
        });
      });
      final repo = StaffRepository(_api(adapter).staff);
      final a = await repo.markAttendance(
        const MarkAttendanceRequest(staffId: staffId, status: 'PRESENT'),
      );
      expect(a.localDate, '2026-10-20');
    });

    test('duplicate attendance surfaces DUPLICATE_ATTENDANCE', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'DUPLICATE_ATTENDANCE',
            'message': 'Already marked',
          },
        });
      });
      final repo = StaffRepository(_api(adapter).staff);
      await expectLater(
        repo.markAttendance(
          const MarkAttendanceRequest(staffId: staffId, status: 'PRESENT'),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'DUPLICATE_ATTENDANCE'),
        ),
      );
    });

    test('corrects attendance and preserves history from response', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/correct'), isTrue);
        expect(options.data['reason'], 'Wrong status');
        return jsonBody(200, {
          'success': true,
          'data': _attendance(withCorrection: true, status: 'ABSENT'),
        });
      });
      final repo = StaffRepository(_api(adapter).staff);
      final a = await repo.correctAttendance(
        attendanceId,
        const CorrectAttendanceRequest(
          status: 'ABSENT',
          reason: 'Wrong status',
        ),
      );
      expect(a.status, 'ABSENT');
      expect(a.correctionHistory, isNotEmpty);
    });

    test('does not invent device timezone date when backend supplies localDate',
        () {
      final a = StaffAttendance.fromJson(_attendance(localDate: '2026-03-15'));
      expect(a.localDate, '2026-03-15');
    });
  });

  group('Shifts', () {
    test('creates shift', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/admin/staff-shifts'), isTrue);
        expect(options.data['startTime'], '22:00');
        expect(options.data['endTime'], '06:00');
        return jsonBody(201, {
          'success': true,
          'data': _shift(
            startTime: '22:00',
            endTime: '06:00',
            startAt: '2026-10-20T16:30:00.000Z',
            endAt: '2026-10-21T00:30:00.000Z',
          ),
        });
      });
      final repo = StaffRepository(_api(adapter).staff);
      final s = await repo.createShift(
        const CreateShiftRequest(
          staffId: staffId,
          shiftDate: '2026-10-20',
          startTime: '22:00',
          endTime: '06:00',
        ),
      );
      expect(s.isOvernight, isTrue);
    });

    test('shift overlap surfaces SHIFT_OVERLAP', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'SHIFT_OVERLAP',
            'message': 'Overlap',
          },
        });
      });
      final repo = StaffRepository(_api(adapter).staff);
      await expectLater(
        repo.createShift(
          const CreateShiftRequest(
            staffId: staffId,
            shiftDate: '2026-10-20',
            startTime: '09:00',
            endTime: '17:00',
          ),
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SHIFT_OVERLAP'),
        ),
      );
    });

    test('updates shift', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.method, 'PATCH');
        return jsonBody(200, {
          'success': true,
          'data': _shift(dutyLocation: 'Gate 2'),
        });
      });
      final repo = StaffRepository(_api(adapter).staff);
      final s = await repo.updateShift(
        shiftId,
        const UpdateShiftRequest(dutyLocation: 'Gate 2'),
      );
      expect(s.dutyLocation, 'Gate 2');
    });
  });

  group('Facility DTO and availability', () {
    test('parses facility with bookingFeePaise', () {
      final f = Facility.fromJson(_facility());
      expect(f.bookingFeePaise, 50000);
      expect(f.feePaymentRequired, isTrue);
      expect(f.availableDays, contains('SATURDAY'));
    });

    test('maps availability from backend', () {
      final a = FacilityAvailability.fromJson(_availability());
      expect(a.remainingCapacityHint, 8);
      expect(a.pendingPolicy.onlyConfirmedCountsTowardCapacity, isTrue);
      expect(a.confirmedSlots, hasLength(1));
    });

    test('parses booking fee and payment status', () {
      final b = FacilityBooking.fromJson(_booking());
      expect(b.feePaiseSnapshot, 50000);
      expect(b.feePaid, isFalse);
      expect(b.feePaymentRequired, isTrue);
      expect(b.status, 'PENDING');
    });

    test('pending expiry display helper', () {
      final expired = FacilityBooking.fromJson(
        _booking(expiresAt: '2020-01-01T00:00:00.000Z'),
      );
      expect(expired.isPendingExpired, isTrue);
      final open = FacilityBooking.fromJson(
        _booking(expiresAt: '2099-01-01T00:00:00.000Z'),
      );
      expect(open.isPendingExpired, isFalse);
    });
  });

  group('Facility bookings', () {
    test('resident creates booking', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(
          options.path.endsWith('/resident/facilities/$facilityId/bookings'),
          isTrue,
        );
        expect(options.data['flatId'], flatId);
        expect(options.data.containsKey('partySize'), isFalse);
        return jsonBody(201, {'success': true, 'data': _booking()});
      });
      final repo = FacilityRepository(_api(adapter).facilities);
      final b = await repo.createBooking(
        facilityId,
        const CreateFacilityBookingRequest(
          flatId: flatId,
          bookingDate: '2026-10-25',
          startTime: '10:00',
          endTime: '12:00',
        ),
      );
      expect(b.status, 'PENDING');
      expect(b.feePaid, isFalse);
    });

    test('capacity conflict surfaces FACILITY_CAPACITY_FULL', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'FACILITY_CAPACITY_FULL',
            'message': 'Full',
          },
        });
      });
      final repo = FacilityRepository(_api(adapter).facilities);
      await expectLater(
        repo.createBooking(
          facilityId,
          const CreateFacilityBookingRequest(
            flatId: flatId,
            bookingDate: '2026-10-25',
            startTime: '10:00',
            endTime: '12:00',
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'FACILITY_CAPACITY_FULL'),
        ),
      );
    });

    test('admin approves pending to confirmed', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/approve'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': _booking(status: 'CONFIRMED'),
        });
      });
      final repo = FacilityRepository(_api(adapter).facilities);
      final b = await repo.approveBooking(bookingId);
      expect(b.status, 'CONFIRMED');
    });

    test('resident cancels booking', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/cancel'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': _booking(status: 'CANCELLED'),
        });
      });
      final repo = FacilityRepository(_api(adapter).facilities);
      final b = await repo.cancelResidentBooking(bookingId, reason: 'Plans changed');
      expect(b.status, 'CANCELLED');
    });

    test('403 residential access', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {
            'code': 'RESIDENTIAL_ACCESS_DENIED',
            'message': 'Denied',
          },
        });
      });
      final repo = FacilityRepository(_api(adapter).facilities);
      await expectLater(
        repo.listResident(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'RESIDENTIAL_ACCESS_DENIED'),
        ),
      );
    });

    test('401 unauthorized', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(401, {
          'success': false,
          'error': {
            'code': 'UNAUTHORIZED',
            'message': 'Unauthorized',
          },
        });
      });
      final repo = FacilityRepository(_api(adapter).facilities);
      await expectLater(
        repo.listAdmin(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'UNAUTHORIZED'),
        ),
      );
    });
  });

  group('Cache invalidation', () {
    test('staff mutation clears staff list cache', () async {
      var calls = 0;
      final adapter = ScriptedAdapter((options) async {
        calls++;
        if (options.path.contains('/deactivate')) {
          return jsonBody(200, {
            'success': true,
            'data': _staff(status: 'INACTIVE'),
          });
        }
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_staff()],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.staff.listStaff();
      await repos.staff.listStaff();
      expect(calls, 1);
      await repos.staff.deactivateStaff(staffId);
      await repos.staff.listStaff();
      expect(calls, greaterThan(2));
    });

    test('facility mutation clears booking caches via LiveRepositories',
        () async {
      var calls = 0;
      final adapter = ScriptedAdapter((options) async {
        calls++;
        if (options.path.contains('/approve')) {
          return jsonBody(200, {
            'success': true,
            'data': _booking(status: 'CONFIRMED'),
          });
        }
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_booking()],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.facilities.listAdminBookings();
      await repos.facilities.listAdminBookings();
      expect(calls, 1);
      await repos.facilities.approveBooking(bookingId);
      await repos.facilities.listAdminBookings();
      expect(calls, greaterThan(2));
    });

    test('invalidateAfterResidentMutation clears facilities', () async {
      var calls = 0;
      final adapter = ScriptedAdapter((options) async {
        calls++;
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_facility()],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.facilities.listResident();
      repos.invalidateAfterResidentMutation();
      await repos.facilities.listResident();
      expect(calls, 2);
    });
  });

  group('Mutation lock', () {
    test('staff mutation lock rejects concurrent action', () async {
      final adapter = ScriptedAdapter((options) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return jsonBody(201, {'success': true, 'data': _staff()});
      });
      final repo = StaffRepository(_api(adapter).staff);
      final first = repo.createStaff(
        const CreateStaffRequest(
          fullName: 'A',
          phone: '9876543210',
          category: 'OTHER',
          employmentType: 'TEMPORARY',
          joiningDate: '2026-01-01',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await expectLater(
        repo.createStaff(
          const CreateStaffRequest(
            fullName: 'B',
            phone: '9876543211',
            category: 'OTHER',
            employmentType: 'TEMPORARY',
            joiningDate: '2026-01-01',
          ),
        ),
        throwsA(isA<StateError>()),
      );
      await first;
    });
  });
}

const societyId = '507f1f77bcf86cd799439011';
const staffId = '507f1f77bcf86cd7994390a1';
const attendanceId = '507f1f77bcf86cd7994390a2';
const shiftId = '507f1f77bcf86cd7994390a3';
const linkedUserId = '507f1f77bcf86cd799439021';
const facilityId = '507f1f77bcf86cd7994390b1';
const bookingId = '507f1f77bcf86cd7994390b2';
const flatId = '507f1f77bcf86cd799439013';

ApnaApi _api(ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4000'));
  dio.httpClientAdapter = adapter;
  final client = ApiClient(
    config: ApiConfig.resolve(flavorName: 'development'),
    dio: dio,
  );
  client.societyId = societyId;
  return ApnaApi(client: client);
}

Map<String, Object?> _staff({
  String status = 'ACTIVE',
  String? linkedUserId,
}) =>
    {
      'id': staffId,
      'societyId': societyId,
      'fullName': 'Ravi Guard',
      'phone': '9876543210',
      'category': 'SECURITY',
      'employmentType': 'PERMANENT',
      'joiningDate': '2026-01-01',
      'employmentStatus': status,
      if (linkedUserId != null) 'linkedUserId': linkedUserId,
      'createdBy': '507f1f77bcf86cd799439099',
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
    };

Map<String, Object?> _attendance({
  String status = 'PRESENT',
  String localDate = '2026-10-20',
  bool withCorrection = false,
}) =>
    {
      'id': attendanceId,
      'societyId': societyId,
      'staffId': staffId,
      'localDate': localDate,
      'status': status,
      'checkInAt': '2026-10-20T03:30:00.000Z',
      'recordedByUserId': '507f1f77bcf86cd799439099',
      'correctionHistory': withCorrection
          ? [
              {
                'correctedByUserId': '507f1f77bcf86cd799439099',
                'correctedAt': '2026-10-20T12:00:00.000Z',
                'previous': {'status': 'PRESENT'},
                'reason': 'Typo',
              },
            ]
          : [],
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
    };

Map<String, Object?> _shift({
  String startTime = '09:00',
  String endTime = '17:00',
  String startAt = '2026-10-20T03:30:00.000Z',
  String endAt = '2026-10-20T11:30:00.000Z',
  String? dutyLocation,
}) =>
    {
      'id': shiftId,
      'societyId': societyId,
      'staffId': staffId,
      'shiftDate': '2026-10-20',
      'startTime': startTime,
      'endTime': endTime,
      'startAt': startAt,
      'endAt': endAt,
      if (dutyLocation != null) 'dutyLocation': dutyLocation,
      'status': 'SCHEDULED',
      'createdBy': '507f1f77bcf86cd799439099',
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
    };

Map<String, Object?> _facility() => {
      'id': facilityId,
      'societyId': societyId,
      'name': 'Clubhouse',
      'category': 'CLUBHOUSE',
      'capacity': 10,
      'bookingRequired': true,
      'requiresApproval': true,
      'maxBookingDurationMinutes': 120,
      'openingTime': '08:00',
      'closingTime': '22:00',
      'availableDays': [
        'MONDAY',
        'TUESDAY',
        'WEDNESDAY',
        'THURSDAY',
        'FRIDAY',
        'SATURDAY',
        'SUNDAY',
      ],
      'isActive': true,
      'bookingFeePaise': 50000,
      'feePaymentRequired': true,
      'createdBy': '507f1f77bcf86cd799439099',
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
    };

Map<String, Object?> _availability() => {
      'facilityId': facilityId,
      'bookingDate': '2026-10-25',
      'capacity': 10,
      'openingTime': '08:00',
      'closingTime': '22:00',
      'confirmedCount': 2,
      'remainingCapacityHint': 8,
      'confirmedSlots': [
        {
          'startAt': '2026-10-25T04:30:00.000Z',
          'endAt': '2026-10-25T06:30:00.000Z',
          'startTime': '10:00',
          'endTime': '12:00',
        },
      ],
      'pendingPolicy': {
        'requiresApproval': true,
        'pendingTtlMs': 1800000,
        'pendingDoesNotConsumeCapacity': true,
        'onlyConfirmedCountsTowardCapacity': true,
      },
    };

Map<String, Object?> _booking({
  String status = 'PENDING',
  String? expiresAt = '2099-01-01T00:00:00.000Z',
}) =>
    {
      'id': bookingId,
      'societyId': societyId,
      'facilityId': facilityId,
      'flatId': flatId,
      'bookedByUserId': '507f1f77bcf86cd799439021',
      'bookingDate': '2026-10-25',
      'startTime': '10:00',
      'endTime': '12:00',
      'startAt': '2026-10-25T04:30:00.000Z',
      'endAt': '2026-10-25T06:30:00.000Z',
      'status': status,
      'feePaiseSnapshot': 50000,
      'feePaid': false,
      'feePaymentRequired': true,
      if (expiresAt != null) 'expiresAt': expiresAt,
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
    };

ResponseBody jsonBody(int status, Object payload) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this._handler);
  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
