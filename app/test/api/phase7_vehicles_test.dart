import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/vehicle_models.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:apna_society/api/repositories/vehicle_repository.dart';
import 'package:apna_society/features/vehicles/vehicle_drafts.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(clearLiveRepositories);

  group('Vehicle DTO and plate helpers', () {
    test('parses vehicle with allocation extras', () {
      final v = Vehicle.fromJson(_vehicle(allocated: true));
      expect(v.registrationNumber, 'MH12AB1234');
      expect(v.vehicleType, 'FOUR_WHEELER');
      expect(v.activeAllocationId, allocationId);
      expect(v.parkingSlotId, slotId);
    });

    test('parses admin list labels for resident-linked vehicles', () {
      final v = Vehicle.fromJson({
        ..._vehicle(),
        'residentName': 'Owner One',
        'flatNumber': 'V-101',
        'wingCode': 'V',
        'societyName': 'Apna Society',
        'societyCode': 'APNA',
        'parkingNumber': 'B-12',
      });
      expect(v.residentName, 'Owner One');
      expect(v.makeModelLabel, 'Honda City');
      expect(v.flatLabel, 'V-101');
      expect(v.societyName, 'Apna Society');
      expect(v.parkingNumber, 'B-12');
      expect(v.parkingLabel, 'B-12');
    });

    test('vehicle drafts skip blanks and reject invalid plates', () {
      final empty = VehicleDraftControllers();
      final valid = VehicleDraftControllers(
        registration: 'mh 12-ab 1234',
        make: 'Honda',
        model: 'City',
      );
      final invalid = VehicleDraftControllers(registration: 'NOPE');
      addTearDown(() {
        empty.dispose();
        valid.dispose();
        invalid.dispose();
      });
      expect(validateVehicleDrafts([empty, valid]), isNull);
      expect(vehicleDraftPayloads([empty, valid]), hasLength(1));
      expect(vehicleDraftPayloads([valid]).first.registrationNumber, 'MH12AB1234');
      expect(validateVehicleDrafts([invalid]), isNotNull);
    });

    test('normalizes and validates Indian plates', () {
      expect(normalizeRegistrationNumber('mh12-ab 1234'), 'MH12AB1234');
      expect(isValidIndianRegistrationNumber('MH12AB1234'), isTrue);
      expect(isValidIndianRegistrationNumber('22BH1234AA'), isTrue);
      expect(isValidIndianRegistrationNumber('BAD'), isFalse);
    });

    test('parses parking slot, summary, allocation, and log', () {
      final slot = ParkingSlot.fromJson(_slot(occupied: true));
      expect(slot.slotNumber, 'B-12');
      expect(slot.isOccupied, isTrue);

      final summary = ParkingSummary.fromJson({
        'totalActiveSlots': 10,
        'occupiedSlots': 4,
        'availableSlots': 6,
        'byParkingType': {'FOUR_WHEELER': 8, 'TWO_WHEELER': 2},
      });
      expect(summary.availableSlots, 6);

      final alloc = ParkingAllocation.fromJson(_allocation());
      expect(alloc.status, 'ACTIVE');

      final log = VehicleLog.fromJson(_log());
      expect(log.status, 'INSIDE');
      expect(log.isRegisteredResidentVehicle, isTrue);
    });
  });

  group('Resident vehicles', () {
    test('lists resident vehicles with flat labels', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.method, 'GET');
        expect(options.path.endsWith('/resident/vehicles'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [
              {
                ..._vehicle(),
                'flatNumber': '101',
                'wingCode': 'A',
              },
            ],
          },
        });
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      final list = await repo.listResident(force: true);
      expect(list.items, hasLength(1));
      expect(list.items.first.flatLabel, 'A-101');
      expect(list.items.first.makeModelLabel, 'Honda City');
    });

    test('resident write APIs surface RESIDENT_VEHICLE_READ_ONLY', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {
            'code': 'RESIDENT_VEHICLE_READ_ONLY',
            'message': 'Read only',
          },
        });
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      await expectLater(
        repo.register(
          const RegisterVehicleRequest(
            flatId: flatId,
            vehicleType: 'FOUR_WHEELER',
            registrationNumber: 'MH12AB1234',
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'RESIDENT_VEHICLE_READ_ONLY'),
        ),
      );
    });

    test('admin registers a vehicle against resident and flat', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.method, 'POST');
        expect(options.path.endsWith('/admin/vehicles'), isTrue);
        expect(options.data['registeredUserId'], '507f1f77bcf86cd799439021');
        expect(options.data['flatId'], flatId);
        return jsonBody(201, {
          'success': true,
          'data': {
            ..._vehicle(),
            'residentName': 'Owner One',
            'flatNumber': '101',
            'wingCode': 'A',
            'societyName': 'Demo Society',
          },
        });
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      final created = await repo.adminRegister(
        const AdminRegisterVehicleRequest(
          flatId: flatId,
          registeredUserId: '507f1f77bcf86cd799439021',
          vehicleType: 'FOUR_WHEELER',
          registrationNumber: 'MH12AB1234',
          make: 'Honda',
          model: 'City',
        ),
      );
      expect(created.residentName, 'Owner One');
      expect(created.flatLabel, 'A-101');
    });

    test('admin duplicate registration surfaces DUPLICATE_VEHICLE', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'DUPLICATE_VEHICLE',
            'message': 'Already registered',
          },
        });
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      await expectLater(
        repo.adminRegister(
          const AdminRegisterVehicleRequest(
            flatId: flatId,
            registeredUserId: '507f1f77bcf86cd799439021',
            vehicleType: 'FOUR_WHEELER',
            registrationNumber: 'MH12AB1234',
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'DUPLICATE_VEHICLE'),
        ),
      );
    });

    test('residential denial is RESIDENTIAL_ACCESS_DENIED', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {
            'code': 'RESIDENTIAL_ACCESS_DENIED',
            'message': 'Denied',
          },
        });
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      await expectLater(
        repo.listResident(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'RESIDENTIAL_ACCESS_DENIED'),
        ),
      );
    });
  });

  group('Admin parking', () {
    test('lists admin vehicles', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/admin/vehicles'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_vehicle()],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      final page = await repo.listAdminVehicles();
      expect(page.items, hasLength(1));
    });

    test('creates and edits parking slots', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.method == 'POST' && options.path.endsWith('/slots')) {
          expect(options.data['parkingType'], 'FOUR_WHEELER');
          return jsonBody(201, {'success': true, 'data': _slot()});
        }
        if (options.method == 'PATCH') {
          final slot = _slot();
          slot['locationDescription'] = 'Basement';
          return jsonBody(200, {
            'success': true,
            'data': slot,
          });
        }
        return notFound(options.path);
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      final created = await repo.createSlot(
        slotNumber: 'B-12',
        parkingType: 'FOUR_WHEELER',
      );
      expect(created.slotNumber, 'B-12');
      final updated = await repo.updateSlot(
        slotId,
        locationDescription: 'Basement',
      );
      expect(updated.id, slotId);
    });

    test('allocation success and incompatible type conflict', () async {
      var call = 0;
      final adapter = ScriptedAdapter((options) async {
        call++;
        if (call == 1) {
          return jsonBody(201, {
            'success': true,
            'data': _allocation(),
          });
        }
        return jsonBody(400, {
          'success': false,
          'error': {
            'code': 'INCOMPATIBLE_SLOT_TYPE',
            'message': 'Type mismatch',
          },
        });
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      final ok = await repo.allocate(
        flatId: flatId,
        vehicleId: vehicleId,
        parkingSlotId: slotId,
      );
      expect(ok.status, 'ACTIVE');
      await expectLater(
        repo.allocate(
          flatId: flatId,
          vehicleId: vehicleId,
          parkingSlotId: slotId,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'INCOMPATIBLE_SLOT_TYPE'),
        ),
      );
    });

    test('duplicate allocation conflict', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'DUPLICATE_ALLOCATION',
            'message': 'Already allocated',
          },
        });
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      await expectLater(
        repo.allocate(
          flatId: flatId,
          vehicleId: vehicleId,
          parkingSlotId: slotId,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'DUPLICATE_ALLOCATION'),
        ),
      );
    });

    test('release allocation and history list', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.contains('/release')) {
          return jsonBody(200, {
            'success': true,
            'data': _allocation(status: 'ENDED'),
          });
        }
        expect(options.path.endsWith('/parking/allocations'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_allocation(status: 'ENDED')],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      final ended = await repo.release(allocationId, reason: 'Moved');
      expect(ended.status, 'ENDED');
      final history = await repo.listAllocations(
        force: true,
        query: const ListAllocationsQuery(status: 'ENDED'),
      );
      expect(history.items.first.status, 'ENDED');
    });
  });

  group('Guard vehicle logs', () {
    test('entry and exit', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/entry')) {
          return jsonBody(201, {'success': true, 'data': _log()});
        }
        expect(options.path.endsWith('/exit'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': _log(status: 'EXITED'),
        });
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      final entry = await repo.recordEntry(
        registrationNumber: 'MH12AB1234',
        vehicleType: 'FOUR_WHEELER',
      );
      expect(entry.status, 'INSIDE');
      final exit = await repo.recordExit(logId: logId);
      expect(exit.status, 'EXITED');
    });

    test('duplicate active entry protection', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final adapter = ScriptedAdapter((options) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return jsonBody(201, {'success': true, 'data': _log()});
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      final first = repo.recordEntry(
        registrationNumber: 'MH12AB1234',
        vehicleType: 'FOUR_WHEELER',
      );
      await entered.future;
      expect(repo.mutationLocked, isTrue);
      await expectLater(
        repo.recordEntry(
          registrationNumber: 'MH12AB1234',
          vehicleType: 'FOUR_WHEELER',
        ),
        throwsA(isA<StateError>()),
      );
      release.complete();
      await first;

      final conflictAdapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'DUPLICATE_ACTIVE_ENTRY',
            'message': 'Already inside',
          },
        });
      });
      final conflictRepo = VehicleRepository(_api(conflictAdapter).vehicles);
      await expectLater(
        conflictRepo.recordEntry(
          registrationNumber: 'MH12AB1234',
          vehicleType: 'FOUR_WHEELER',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'DUPLICATE_ACTIVE_ENTRY'),
        ),
      );
    });
  });

  group('Cache and auth', () {
    test('cache invalidation after mutation', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/resident/vehicles') &&
            options.method == 'GET') {
          return jsonBody(200, {
            'success': true,
            'data': {
              'items': [_vehicle()],
            },
          });
        }
        if (options.method == 'POST' &&
            options.path.contains('/deactivate')) {
          final v = _vehicle();
          v['isActive'] = false;
          return jsonBody(200, {
            'success': true,
            'data': v,
          });
        }
        return notFound(options.path);
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.vehicles.listResident();
      expect(repos.vehicles.lastResidentVehicles, isNotNull);
      await repos.vehicles.deactivate(vehicleId);
      expect(repos.vehicles.lastResidentVehicles, isNull);
    });

    test('403 without inventing success', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {'code': 'FORBIDDEN_ROLE', 'message': 'Forbidden'},
        });
      });
      final repo = VehicleRepository(_api(adapter).vehicles);
      await expectLater(
        repo.listAdminVehicles(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'FORBIDDEN_ROLE'),
        ),
      );
      expect(repo.lastAdminVehicles, isNull);
    });
  });
}

const societyId = '507f1f77bcf86cd799439011';
const flatId = '507f1f77bcf86cd799439013';
const vehicleId = '507f1f77bcf86cd799439091';
const slotId = '507f1f77bcf86cd799439092';
const allocationId = '507f1f77bcf86cd799439093';
const logId = '507f1f77bcf86cd799439094';

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

Map<String, Object?> _vehicle({bool allocated = false}) => {
      'id': vehicleId,
      'societyId': societyId,
      'flatId': flatId,
      'registeredUserId': '507f1f77bcf86cd799439021',
      'vehicleType': 'FOUR_WHEELER',
      'registrationNumber': 'MH12AB1234',
      'make': 'Honda',
      'model': 'City',
      'colour': 'White',
      'isActive': true,
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
      if (allocated) 'activeAllocationId': allocationId,
      if (allocated) 'parkingSlotId': slotId,
    };

Map<String, Object?> _slot({bool occupied = false}) => {
      'id': slotId,
      'societyId': societyId,
      'slotNumber': 'B-12',
      'parkingType': 'FOUR_WHEELER',
      'locationDescription': 'Basement',
      'isActive': true,
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
      'isOccupied': occupied,
      if (occupied) 'activeAllocationId': allocationId,
    };

Map<String, Object?> _allocation({String status = 'ACTIVE'}) => {
      'id': allocationId,
      'societyId': societyId,
      'flatId': flatId,
      'vehicleId': vehicleId,
      'parkingSlotId': slotId,
      'startsAt': '2026-10-20T10:00:00.000Z',
      'status': status,
      'createdBy': '507f1f77bcf86cd799439001',
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
      if (status == 'ENDED') 'endsAt': '2026-10-21T10:00:00.000Z',
    };

Map<String, Object?> _log({String status = 'INSIDE'}) => {
      'id': logId,
      'societyId': societyId,
      'vehicleId': vehicleId,
      'flatId': flatId,
      'registrationNumber': 'MH12AB1234',
      'vehicleType': 'FOUR_WHEELER',
      'status': status,
      'entryAt': '2026-10-20T10:00:00.000Z',
      if (status == 'EXITED') 'exitAt': '2026-10-20T12:00:00.000Z',
      'guardUserId': '507f1f77bcf86cd799439081',
      'isRegisteredResidentVehicle': true,
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
    };

ResponseBody notFound(String path) => jsonBody(404, {
      'success': false,
      'error': {'code': 'ROUTE_NOT_FOUND', 'message': path},
    });

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
