import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/auth/app_role.dart';
import 'package:apna_society/api/auth/auth_session.dart';
import 'package:apna_society/api/auth/home_resolver.dart';
import 'package:apna_society/api/auth/secure_token_store.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/common.dart';
import 'package:apna_society/api/models/resident_home_context.dart';
import 'package:apna_society/api/models/resident_models.dart';
import 'package:apna_society/api/models/society_models.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:apna_society/api/repositories/resident_repository.dart';
import 'package:apna_society/api/repositories/society_repository.dart';
import 'package:apna_society/services/occupancy_access.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const societyId = '507f1f77bcf86cd799439011';
const wingId = '507f1f77bcf86cd799439012';
const flatId = '507f1f77bcf86cd799439013';
const flatId2 = '507f1f77bcf86cd799439014';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  tearDown(() {
    clearLiveRepositories();
    resetAuthSessionForTests();
  });

  group('SocietyRepository', () {
    test('maps society, wings, flats pagination and dashboard', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/admin/society')) {
          return jsonBody(200, {'success': true, 'data': _society(societyId)});
        }
        if (options.path.endsWith('/admin/wings')) {
          return jsonBody(200, {
            'success': true,
            'data': [_wing(societyId, wingId)],
          });
        }
        if (options.path.endsWith('/admin/flats')) {
          expect('${options.queryParameters['page']}', '1');
          expect('${options.queryParameters['limit']}', '20');
          return jsonBody(200, {
            'success': true,
            'data': {
              'items': [_flat(societyId, wingId, flatId)],
              'pagination': {
                'page': 1,
                'limit': 20,
                'total': 1,
                'totalPages': 1,
              },
            },
          });
        }
        if (options.path.endsWith('/admin/dashboard')) {
          return jsonBody(200, {
            'success': true,
            'data': _dashboard(societyId, wingId),
          });
        }
        return notFound(options.path);
      });
      final repo = SocietyRepository(_api(adapter).society);

      final society = await repo.society();
      expect(society.id, societyId);
      expect(society.name, 'Monarch Solitaire');

      final wings = await repo.wings();
      expect(wings, hasLength(1));
      expect(wings.first.id, wingId);

      final flats = await repo.listFlats(
        query: const ListFlatsQuery(page: 1, limit: 20),
      );
      expect(flats.items, hasLength(1));
      expect(flats.items.first.id, flatId);
      expect(flats.pagination.total, 1);
      expect(isObjectId(flats.items.first.id), isTrue);

      final dash = await repo.dashboard();
      expect(dash.totals.flats, 140);
      expect(dash.totals.monthlyMaintenanceTotal, 588000);
      expect(dash.wings.first.code, 'A');
    });

    test('dedupes concurrent dashboard requests', () async {
      var calls = 0;
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/admin/dashboard')) {
          calls += 1;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return jsonBody(200, {
            'success': true,
            'data': _dashboard(societyId, wingId),
          });
        }
        return notFound(options.path);
      });
      final repo = SocietyRepository(_api(adapter).society);
      final results = await Future.wait([
        repo.dashboard(),
        repo.dashboard(),
        repo.dashboard(),
      ]);
      expect(calls, 1);
      expect(results.every((r) => r.totals.flats == 140), isTrue);
    });

    test('API failure does not invent SQLite fallback data', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(500, {
          'success': false,
          'error': {
            'code': 'INTERNAL_ERROR',
            'message': 'boom',
            'requestId': 'r1',
          },
        });
      });
      final repo = SocietyRepository(_api(adapter).society);
      await expectLater(repo.society(), throwsA(isA<ApiException>()));
      expect(repo.lastFlatsPage, isNull);
    });
  });

  group('ResidentRepository and home context', () {
    test('maps profile, multiple flats, and owner access flags', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/resident/profile')) {
          return jsonBody(200, {
            'success': true,
            'data': {
              'id': 'user-1',
              'email': 'owner@example.com',
              'name': 'Owner One',
              'phone': '9876510032',
              'roles': ['OWNER'],
              'societyIds': [societyId],
              'activeFlatIds': [flatId, flatId2],
            },
          });
        }
        if (options.path.endsWith('/resident/flats')) {
          return jsonBody(200, {
            'success': true,
            'data': [
              _residentFlat(societyId, wingId, flatId, role: 'OWNER'),
              _residentFlat(
                societyId,
                wingId,
                flatId2,
                number: 'A-102',
                role: 'OWNER',
                financial: true,
                residential: true,
              ),
            ],
          });
        }
        return notFound(options.path);
      });
      final repo = ResidentRepository(_api(adapter).residents);
      final profile = await repo.profile();
      final flats = await repo.flats();
      expect(profile.activeFlatIds, [flatId, flatId2]);
      expect(flats, hasLength(2));

      final home = ResidentHomeContext.fromBackend(
        profile: profile,
        flats: flats,
        preferOwner: true,
      );
      expect(home.hasMultipleFlats, isTrue);
      expect(home.accessibleFlats, hasLength(2));
      expect(home.access.canFinance, isTrue);
      expect(home.flatNumber, 'A-101');
      expect(home.wingLabel, 'Wing A');
    });

    test('tenant financial access denial from backend flags', () {
      final profile = ResidentProfile(
        id: 'u1',
        email: 't@example.com',
        name: 'Tenant',
        roles: const ['TENANT'],
        societyIds: const [societyId],
        activeFlatIds: const [flatId],
      );
      final flats = [
        ResidentFlat.fromJson(_residentFlat(
          societyId,
          wingId,
          flatId,
          role: 'TENANT',
          financial: false,
          residential: true,
          occupancy: 'TENANT_OCCUPIED',
        )),
      ];
      final home = ResidentHomeContext.fromBackend(
        profile: profile,
        flats: flats,
        preferOwner: false,
      );
      expect(home.access.canFinance, isFalse);
      expect(home.access.canResidential, isTrue);
      expect(home.access.isTenantSession, isTrue);
      expect(() => home.access.assertFinance(), throwsA(isA<StateError>()));
    });

    test('owner access flags follow backend occupancy', () {
      final access = OccupancyAccess.fromBackend(
        financial: true,
        residential: false,
        backendRole: 'OWNER',
        occupancyStatus: 'TENANT_OCCUPIED',
        displayName: 'Owner',
      );
      expect(access.canFinance, isTrue);
      expect(access.canResidential, isFalse);
      expect(access.isTenantOccupied, isTrue);
    });
  });

  group('HomeResolver routing', () {
    test('routes admin without SQLite identity bridge', () async {
      final session = await _authenticatedSession(
        roles: ['ADMIN'],
        flats: const [],
      );
      final dest = await HomeResolver(session).resolve();
      expect(dest.kind, HomeDestinationKind.admin);
      expect(dest.resident, isNull);
    });

    test('routes owner from backend flats, not flat-number matching', () async {
      final session = await _authenticatedSession(
        roles: ['OWNER'],
        flats: [
          _residentFlat(societyId, wingId, flatId, role: 'OWNER'),
        ],
      );
      final dest = await HomeResolver(session).resolve();
      expect(dest.kind, HomeDestinationKind.resident);
      expect(dest.resident!.flat.id, flatId);
      expect(dest.resident!.flat.number, 'A-101');
      expect(dest.resident!.access.canFinance, isTrue);
    });

    test('dropdown role mismatch still follows backend authorization', () async {
      final session = await _authenticatedSession(
        roles: ['TENANT'],
        flats: [
          _residentFlat(
            societyId,
            wingId,
            flatId,
            role: 'TENANT',
            financial: false,
            residential: true,
            occupancy: 'TENANT_OCCUPIED',
          ),
        ],
      );
      expect(session.appRole, AppRole.tenant);
      expect(tryParseDropdownRole('owner'), AppRole.owner);
      expect(tryParseDropdownRole('owner'), isNot(session.appRole));
      final dest = await HomeResolver(session).resolve();
      expect(dest.resident!.access.isTenantSession, isTrue);
      expect(dest.resident!.access.canFinance, isFalse);
    });

    test('guard destination uses profile display, not demo guard row', () async {
      final session = await _authenticatedSession(
        roles: ['GUARD'],
        flats: const [],
        name: 'Gate Guard',
        phone: '9876500099',
      );
      final dest = await HomeResolver(session).resolve();
      expect(dest.kind, HomeDestinationKind.guard);
      expect(dest.guard!.name, 'Gate Guard');
      expect(dest.guard!.mobile, '9876500099');
      expect(dest.guard!.id, 0);
    });
  });

  group('Cache clearing', () {
    test('logout and clearLocal wipe user-specific live caches', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/admin/society')) {
          return jsonBody(200, {'success': true, 'data': _society(societyId)});
        }
        if (options.path.endsWith('/auth/logout')) {
          return jsonBody(200, {
            'success': true,
            'data': {'message': 'Logged out'},
          });
        }
        return notFound(options.path);
      });
      final store = MemorySecureTokenStore();
      final session = _session(adapter, store: store);
      session.debugSetAccessToken('access');
      await store.writeRefreshToken('refresh');
      final repos = ensureLiveRepositories(session.api);
      await repos.society.society();
      expect(liveRepositories, isNotNull);

      await performLogout(session);
      expect(liveRepositories, isNull);
      expect(await store.readRefreshToken(), isNull);
    });
  });

  group('Presentation labels', () {
    test('flat type and occupancy labels', () {
      expect(flatTypeLabel('2BHK'), '2 BHK');
      expect(flatTypeLabel('3BHK'), '3 BHK');
      expect(occupancyStatusLabel('TENANT_OCCUPIED'), 'Tenant occupied');
      expect(occupancyStatusLabel('VACANT'), 'Vacant');
    });
  });
}

Future<AuthSession> _authenticatedSession({
  required List<String> roles,
  required List<Map<String, Object?>> flats,
  String name = 'User',
  String? phone,
}) async {
  final adapter = ScriptedAdapter((options) async {
    if (options.path.endsWith('/me')) {
      return jsonBody(200, {
        'success': true,
        'data': {
          'id': 'user-1',
          'email': 'user@example.com',
          'name': name,
          if (phone != null) 'phone': phone,
          'roles': roles,
          'societyIds': [societyId],
          'primarySocietyId': societyId,
        },
      });
    }
    if (options.path.endsWith('/resident/profile')) {
      return jsonBody(200, {
        'success': true,
        'data': {
          'id': 'user-1',
          'email': 'user@example.com',
          'name': name,
          if (phone != null) 'phone': phone,
          'roles': roles.where((r) => r == 'OWNER' || r == 'TENANT').toList(),
          'societyIds': [societyId],
          'activeFlatIds': flats.map((f) => f['id']).toList(),
        },
      });
    }
    if (options.path.endsWith('/resident/flats')) {
      return jsonBody(200, {'success': true, 'data': flats});
    }
    return notFound(options.path);
  });
  final session = _session(adapter);
  session.debugSetAccessToken('access');
  await session.loadProfileAndContext();
  return session;
}

ApnaApi _api(ScriptedAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4000'));
  dio.httpClientAdapter = adapter;
  final client = ApiClient(
    config: ApiConfig.resolve(flavorName: 'development'),
    dio: dio,
  );
  return ApnaApi(client: client);
}

AuthSession _session(
  ScriptedAdapter adapter, {
  MemorySecureTokenStore? store,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4000'));
  dio.httpClientAdapter = adapter;
  final client = ApiClient(
    config: ApiConfig.resolve(flavorName: 'development'),
    dio: dio,
  );
  return AuthSession(
    client: client,
    tokenStore: store ?? MemorySecureTokenStore(),
    api: ApnaApi(client: client),
  );
}

Map<String, Object?> _society(String id) => {
      'id': id,
      'name': 'Monarch Solitaire',
      'code': 'MSA',
      'timezone': 'Asia/Kolkata',
      'currency': 'INR',
      'maintenanceDayOfMonth': 1,
      'isActive': true,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
      'city': 'Pune',
    };

Map<String, Object?> _wing(String societyId, String wingId) => {
      'id': wingId,
      'societyId': societyId,
      'name': 'Wing A',
      'code': 'A',
      'floors': 7,
      'flatsPerFloor': 4,
      'sortOrder': 1,
      'isActive': true,
      'flatCount': 28,
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
    };

Map<String, Object?> _flat(String societyId, String wingId, String id) => {
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
      'occupancyStatus': 'OWNER_OCCUPIED',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'updatedAt': '2026-01-01T00:00:00.000Z',
    };

Map<String, Object?> _residentFlat(
  String societyId,
  String wingId,
  String id, {
  String number = 'A-101',
  String role = 'OWNER',
  bool financial = true,
  bool residential = true,
  String occupancy = 'OWNER_OCCUPIED',
}) =>
    {
      ..._flat(societyId, wingId, id),
      'number': number,
      'occupancyStatus': occupancy,
      'access': {
        'financial': financial,
        'residential': residential,
        'role': role,
      },
    };

Map<String, Object?> _dashboard(String societyId, String wingId) => {
      'totals': {
        'wings': 5,
        'flats': 140,
        'activeFlats': 140,
        'inactiveFlats': 0,
        'ownerOccupiedFlats': 100,
        'tenantOccupiedFlats': 20,
        'vacantFlats': 20,
        'twoBhkCount': 112,
        'threeBhkCount': 28,
        'monthlyMaintenanceTotal': 588000,
      },
      'wings': [
        {
          'id': wingId,
          'code': 'A',
          'name': 'Wing A',
          'flatCount': 28,
          'activeFlats': 28,
          'inactiveFlats': 0,
          'ownerOccupiedFlats': 20,
          'tenantOccupiedFlats': 4,
          'vacantFlats': 4,
          'twoBhkCount': 22,
          'threeBhkCount': 6,
          'monthlyMaintenanceTotal': 117600,
        },
      ],
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
