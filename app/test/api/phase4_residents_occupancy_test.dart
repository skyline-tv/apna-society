import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/auth/admin_api_messages.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/admin_user_models.dart';
import 'package:apna_society/api/repositories/admin_user_repository.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:apna_society/api/repositories/society_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const societyId = '507f1f77bcf86cd799439011';
  const wingId = '507f1f77bcf86cd799439012';
  const flatId = '507f1f77bcf86cd799439013';
  const ownerId = '507f1f77bcf86cd799439021';
  const tenantId = '507f1f77bcf86cd799439022';

  tearDown(clearLiveRepositories);

  group('Provisioning', () {
    test('owner provisioning creates a new account', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path, '/api/v1/admin/users');
        expect(options.method, 'POST');
        expect(options.data['role'], 'OWNER');
        expect(options.data['email'], 'owner@example.com');
        return jsonBody(201, {
          'success': true,
          'data': {
            'user': _user(ownerId, role: 'OWNER'),
            'reusedExisting': false,
            'flatAssigned': false,
          },
        });
      });
      final repo = AdminUserRepository(_api(adapter).adminUsers);
      final result = await repo.provision(
        name: 'Owner One',
        email: 'owner@example.com',
        role: 'OWNER',
      );
      expect(result.reusedExisting, isFalse);
      expect(result.user.id, ownerId);
      expect(result.flatAssigned, isFalse);
    });

    test('tenant provisioning reuses existing account', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(201, {
          'success': true,
          'data': {
            'user': _user(tenantId, role: 'TENANT', email: 't@example.com'),
            'reusedExisting': true,
            'flatAssigned': false,
          },
        });
      });
      final repo = AdminUserRepository(_api(adapter).adminUsers);
      final result = await repo.provision(
        name: 'Tenant',
        email: 't@example.com',
        role: 'TENANT',
      );
      expect(result.reusedExisting, isTrue);
      expect(result.user.email, 't@example.com');
    });

    test('failed provision does not invent a local user', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'DUPLICATE_EMAIL',
            'message': 'A user with this email already exists',
          },
        });
      });
      final repo = AdminUserRepository(_api(adapter).adminUsers);
      await expectLater(
        repo.provision(
          name: 'X',
          email: 'x@example.com',
          role: 'OWNER',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(repo.lastList, isNull);
    });
  });

  group('Occupancy lifecycle', () {
    test('assigns owner and invalidates flat caches', () async {
      var assignCalls = 0;
      var flatStatus = 'VACANT';
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/assign-owner')) {
          assignCalls += 1;
          expect(options.data['userId'], ownerId);
          flatStatus = 'OWNER_OCCUPIED';
          return jsonBody(201, {
            'success': true,
            'data': {
              'flatId': flatId,
              'occupancyStatus': 'OWNER_OCCUPIED',
              'activeOwnerUserId': ownerId,
              'activeTenantUserId': null,
            },
          });
        }
        if (options.path.endsWith('/admin/flats/$flatId') &&
            options.method == 'GET') {
          return jsonBody(200, {
            'success': true,
            'data': _flat(
              societyId,
              wingId,
              flatId,
              status: flatStatus,
              ownerId: flatStatus == 'OWNER_OCCUPIED' ? ownerId : null,
            ),
          });
        }
        return notFound(options.path);
      });
      final api = _api(adapter);
      final repos = ensureLiveRepositories(api);
      // Seed a stale flat cache entry.
      final before = await repos.society.flat(flatId);
      expect(before.occupancyStatus, 'VACANT');
      final result = await repos.society.assignOwner(
        flatId,
        userId: ownerId,
        effectiveFrom: DateTime.utc(2026, 3, 1),
      );
      expect(assignCalls, 1);
      expect(result.occupancyStatus, 'OWNER_OCCUPIED');
      expect(repos.society.lastFlatsPage, isNull);
      // Force reload after invalidation.
      final refreshed = await repos.society.flat(flatId, force: true);
      expect(refreshed.occupancyStatus, 'OWNER_OCCUPIED');
    });

    test('assigns tenant on owner-occupied flat', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/assign-tenant'), isTrue);
        return jsonBody(201, {
          'success': true,
          'data': {
            'flatId': flatId,
            'occupancyStatus': 'TENANT_OCCUPIED',
            'activeOwnerUserId': ownerId,
            'activeTenantUserId': tenantId,
          },
        });
      });
      final repo = SocietyRepository(_api(adapter).society);
      final result = await repo.assignTenant(
        flatId,
        userId: tenantId,
        effectiveFrom: DateTime.utc(2026, 4, 1),
      );
      expect(result.occupancyStatus, 'TENANT_OCCUPIED');
      expect(result.activeTenantUserId, tenantId);
    });

    test('duplicate assignment is rejected without local fallback', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'DUPLICATE_ACTIVE_ASSIGNMENT',
            'message': 'User already has an active owner assignment',
          },
        });
      });
      final repo = SocietyRepository(_api(adapter).society);
      await expectLater(
        repo.assignOwner(
          flatId,
          userId: ownerId,
          effectiveFrom: DateTime.now(),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'DUPLICATE_ACTIVE_ASSIGNMENT',
          ),
        ),
      );
    });

    test('ends tenant occupancy', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/end-tenant-occupancy'), isTrue);
        expect(options.data['reason'], 'Lease ended');
        return jsonBody(200, {
          'success': true,
          'data': {
            'flatId': flatId,
            'occupancyStatus': 'OWNER_OCCUPIED',
            'activeOwnerUserId': ownerId,
            'activeTenantUserId': null,
          },
        });
      });
      final repo = SocietyRepository(_api(adapter).society);
      final result = await repo.endTenantOccupancy(
        flatId,
        effectiveTo: DateTime.utc(2026, 5, 1),
        reason: 'Lease ended',
      );
      expect(result.occupancyStatus, 'OWNER_OCCUPIED');
      expect(result.activeTenantUserId, isNull);
    });

    test('ends owner occupancy when tenant is gone', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/end-owner-occupancy'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'flatId': flatId,
            'occupancyStatus': 'VACANT',
            'activeOwnerUserId': null,
            'activeTenantUserId': null,
          },
        });
      });
      final repo = SocietyRepository(_api(adapter).society);
      final result = await repo.endOwnerOccupancy(
        flatId,
        effectiveTo: DateTime.utc(2026, 6, 1),
        reason: 'Sold flat',
      );
      expect(result.occupancyStatus, 'VACANT');
    });

    test('ending owner while tenant active is rejected', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {
            'code': 'TENANT_STILL_ACTIVE',
            'message': 'End tenant occupancy before ending owner occupancy',
          },
        });
      });
      final repo = SocietyRepository(_api(adapter).society);
      await expectLater(
        repo.endOwnerOccupancy(
          flatId,
          effectiveTo: DateTime.now(),
          reason: 'Too soon',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'TENANT_STILL_ACTIVE',
          ),
        ),
      );
    });

    test('loads occupancy history with preserved records', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/occupancy-history'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'flatId': flatId,
            'occupancyStatus': 'OWNER_OCCUPIED',
            'activeOwnerUserId': ownerId,
            'activeTenantUserId': null,
            'items': [
              {
                'id': '507f1f77bcf86cd799439031',
                'userId': ownerId,
                'userName': 'Owner One',
                'userEmail': 'owner@example.com',
                'role': 'OWNER',
                'status': 'ACTIVE',
                'startsAt': '2026-03-01T00:00:00.000Z',
              },
              {
                'id': '507f1f77bcf86cd799439032',
                'userId': tenantId,
                'userName': 'Tenant',
                'userEmail': 't@example.com',
                'role': 'TENANT',
                'status': 'ENDED',
                'startsAt': '2026-01-01T00:00:00.000Z',
                'endsAt': '2026-02-28T00:00:00.000Z',
                'endReason': 'Lease ended',
              },
            ],
            'pagination': {
              'page': 1,
              'limit': 50,
              'total': 2,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = SocietyRepository(_api(adapter).society);
      final history = await repo.occupancyHistory(flatId);
      expect(history.items, hasLength(2));
      expect(history.items.any((i) => i.status == 'ENDED'), isTrue);
      expect(history.items.first.userName, 'Owner One');
    });
  });

  group('Authorization and messaging', () {
    test('unauthorized role surfaces forbidden message', () {
      expect(
        adminApiErrorMessage(ApiException(
          code: 'FORBIDDEN',
          message: 'Admin role required',
          statusCode: 403,
        )),
        'You are not allowed to perform this action.',
      );
    });

    test('cache invalidation after resident mutation clears lists', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/admin/users') && options.method == 'GET') {
          return jsonBody(200, {
            'success': true,
            'data': {
              'items': [_user(ownerId, role: 'OWNER')],
              'pagination': {
                'page': 1,
                'limit': 20,
                'total': 1,
                'totalPages': 1,
              },
            },
          });
        }
        return notFound(options.path);
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.users.listUsers(
        query: const ListUsersQuery(role: 'OWNER', page: 1, limit: 20),
      );
      expect(repos.users.lastList, isNotNull);
      repos.invalidateAfterResidentMutation(flatId: flatId);
      expect(repos.users.lastList, isNull);
      expect(repos.society.lastFlatsPage, isNull);
    });
  });
}

ApnaApi _api(ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4000'));
  dio.httpClientAdapter = adapter;
  final client = ApiClient(
    config: ApiConfig.resolve(flavorName: 'development'),
    dio: dio,
  );
  client.societyId = '507f1f77bcf86cd799439011';
  return ApnaApi(client: client);
}

Map<String, Object?> _user(
  String id, {
  required String role,
  String email = 'owner@example.com',
}) =>
    {
      'id': id,
      'email': email,
      'name': 'User',
      'roles': [role],
      'isActive': true,
      'canLogin': true,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
    };

Map<String, Object?> _flat(
  String societyId,
  String wingId,
  String id, {
  String status = 'VACANT',
  String? ownerId,
}) =>
    {
      'id': id,
      'societyId': societyId,
      'wingId': wingId,
      'wingCode': 'A',
      'wingName': 'Wing A',
      'number': 'A-101',
      'floor': 1,
      'position': 1,
      'flatType': '2BHK',
      'maintenanceRate': 4000,
      'isActive': true,
      'occupancyStatus': status,
      if (ownerId != null)
        'activeOwner': {
          'id': ownerId,
          'name': 'Owner',
          'email': 'owner@example.com',
          'role': 'OWNER',
        },
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
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
