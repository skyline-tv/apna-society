import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/admin_guard_models.dart';
import 'package:apna_society/api/repositories/admin_guard_repository.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(clearLiveRepositories);

  group('Guard DTO parsing', () {
    test('parses guard with membership and login flags', () {
      final g = AdminGuard.fromJson(_guard());
      expect(g.id, guardId);
      expect(g.name, 'Gate Guard');
      expect(g.username, 'gate1');
      expect(g.phone, '+91 9000000001');
      expect(g.roles, ['GUARD']);
      expect(g.membershipActive, isTrue);
      expect(g.canLogin, isTrue);
      expect(g.mustChangePassword, isTrue);
    });

    test('parses provision result and one-time password', () {
      final r = ProvisionGuardResult.fromJson({
        'guard': _guard(),
        'reusedExisting': false,
        'temporaryPassword': 'TempPassw0rd!',
        'mustChangePassword': true,
        'passwordGenerated': true,
      });
      expect(r.guard.id, guardId);
      expect(r.reusedExisting, isFalse);
      expect(r.temporaryPassword, 'TempPassw0rd!');
      expect(r.passwordGenerated, isTrue);
    });
  });

  group('Admin guard API', () {
    test('provisions a guard with name, email, phone and username', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/admin/guards'), isTrue);
        expect(options.method, 'POST');
        expect(options.data['name'], 'Gate Guard');
        expect(options.data['email'], 'gate@example.com');
        expect(options.data['phone'], '+91 9000000001');
        expect(options.data['username'], 'gate1');
        return jsonBody(201, {
          'success': true,
          'data': {
            'guard': _guard(),
            'reusedExisting': false,
            'temporaryPassword': 'TempPassw0rd!',
            'mustChangePassword': true,
            'passwordGenerated': true,
          },
        });
      });
      final repo = AdminGuardRepository(_api(adapter).adminGuards);
      final created = await repo.provision(
        const CreateGuardRequest(
          name: 'Gate Guard',
          email: 'gate@example.com',
          phone: '+91 9000000001',
          username: 'gate1',
        ),
      );
      expect(created.guard.roles, contains('GUARD'));
      expect(created.temporaryPassword, 'TempPassw0rd!');
    });

    test('lists guards with active membership filter', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/admin/guards'), isTrue);
        expect(options.queryParameters['isActive'], 'true');
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_guard()],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = AdminGuardRepository(_api(adapter).adminGuards);
      final page = await repo.listGuards(
        query: const ListGuardsQuery(isActive: true, limit: 20),
      );
      expect(page.items, hasLength(1));
      expect(page.items.first.membershipActive, isTrue);
    });

    test('updates name and phone', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/admin/guards/$guardId'), isTrue);
        expect(options.method, 'PATCH');
        expect(options.data['name'], 'Night Guard');
        expect(options.data['phone'], '+91 9000000002');
        return jsonBody(200, {
          'success': true,
          'data': _guard(name: 'Night Guard', phone: '+91 9000000002'),
        });
      });
      final repo = AdminGuardRepository(_api(adapter).adminGuards);
      final updated = await repo.updateGuard(
        guardId,
        const UpdateGuardRequest(
          name: 'Night Guard',
          phone: '+91 9000000002',
        ),
      );
      expect(updated.name, 'Night Guard');
      expect(updated.phone, '+91 9000000002');
    });

    test('deactivates a guard', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(
          options.path.endsWith('/admin/guards/$guardId/deactivate'),
          isTrue,
        );
        expect(options.method, 'POST');
        expect(options.data['reason'], 'Shift ended');
        return jsonBody(200, {
          'success': true,
          'data': _guard(membershipActive: false, canLogin: false),
        });
      });
      final repo = AdminGuardRepository(_api(adapter).adminGuards);
      final updated =
          await repo.deactivateGuard(guardId, reason: 'Shift ended');
      expect(updated.membershipActive, isFalse);
      expect(updated.canLogin, isFalse);
    });

    test('duplicate guard surfaces DUPLICATE_GUARD', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'DUPLICATE_GUARD',
            'message': 'User already has an active guard membership',
          },
        });
      });
      final repo = AdminGuardRepository(_api(adapter).adminGuards);
      await expectLater(
        repo.provision(
          const CreateGuardRequest(
            name: 'Gate Guard',
            email: 'gate@example.com',
          ),
        ),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'DUPLICATE_GUARD')),
      );
    });

    test('mutation invalidates list cache', () async {
      var lists = 0;
      final adapter = ScriptedAdapter((options) async {
        if (options.method == 'GET' && options.path.endsWith('/admin/guards')) {
          lists++;
          return jsonBody(200, {
            'success': true,
            'data': {
              'items': [_guard()],
              'pagination': {
                'page': 1,
                'limit': 20,
                'total': 1,
                'totalPages': 1,
              },
            },
          });
        }
        if (options.path.endsWith('/admin/guards/$guardId/deactivate')) {
          return jsonBody(200, {
            'success': true,
            'data': _guard(membershipActive: false),
          });
        }
        return jsonBody(404, {
          'success': false,
          'error': {'code': 'NOT_FOUND', 'message': options.path},
        });
      });
      final repos = LiveRepositories(_api(adapter));
      await repos.guards.listGuards();
      await repos.guards.listGuards();
      expect(lists, 1);
      await repos.guards.deactivateGuard(guardId);
      await repos.guards.listGuards();
      expect(lists, 2);
    });
  });
}

const societyId = '507f1f77bcf86cd799439011';
const guardId = '507f1f77bcf86cd799439031';

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

Map<String, Object?> _guard({
  String name = 'Gate Guard',
  String phone = '+91 9000000001',
  bool membershipActive = true,
  bool canLogin = true,
}) =>
    {
      'id': guardId,
      'email': 'gate@example.com',
      'username': 'gate1',
      'name': name,
      'phone': phone,
      'roles': ['GUARD'],
      'isActive': true,
      'canLogin': canLogin,
      'mustChangePassword': true,
      'primarySocietyId': societyId,
      'membershipActive': membershipActive,
      'membershipStartsAt': '2026-10-01T00:00:00.000Z',
      'createdAt': '2026-10-01T00:00:00.000Z',
      'updatedAt': '2026-10-01T00:00:00.000Z',
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
