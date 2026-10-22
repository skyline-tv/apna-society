import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/society_models.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:apna_society/api/repositories/society_repository.dart';
import 'package:apna_society/features/announcements/announcement_flat_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(clearLiveRepositories);

  group('listAllFlats pagination', () {
    test('fetches more than 100 flats across pages without hardcoding 140',
        () async {
      final adapter = ScriptedAdapter((options) async {
        final page = int.parse('${options.queryParameters['page'] ?? 1}');
        final limit = int.parse('${options.queryParameters['limit'] ?? 100}');
        expect(limit, lessThanOrEqualTo(100));
        final total = 140;
        final totalPages = (total / limit).ceil();
        final start = (page - 1) * limit;
        final end = (start + limit).clamp(0, total);
        final items = [
          for (var i = start; i < end; i++) _flat(i),
        ];
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': items,
            'pagination': {
              'page': page,
              'limit': limit,
              'total': total,
              'totalPages': totalPages,
            },
          },
        });
      });
      final repo = SocietyRepository(_api(adapter).society);
      final flats = await repo.listAllFlats();
      expect(flats, hasLength(140));
      expect(flats.first.number, 'F-0');
      expect(flats.last.number, 'F-139');
      expect(flats.map((f) => f.id).toSet(), hasLength(140));
    });

    test('deduplicates flat ids across pages', () async {
      var calls = 0;
      final adapter = ScriptedAdapter((options) async {
        calls++;
        final page = int.parse('${options.queryParameters['page'] ?? 1}');
        // Page 2 repeats first item of page 1.
        final items = page == 1
            ? [_flat(0), _flat(1)]
            : [_flat(0), _flat(2)];
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': items,
            'pagination': {
              'page': page,
              'limit': 2,
              'total': 3,
              'totalPages': 2,
            },
          },
        });
      });
      final repo = SocietyRepository(_api(adapter).society);
      final flats = await repo.listAllFlats(pageSize: 2);
      expect(calls, 2);
      expect(flats.map((f) => f.id).toList(), [
        _flatId(0),
        _flatId(1),
        _flatId(2),
      ]);
    });

    test('surfaces API pagination failure', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(500, {
          'success': false,
          'error': {
            'code': 'INTERNAL_ERROR',
            'message': 'Boom',
          },
        });
      });
      final repo = SocietyRepository(_api(adapter).society);
      await expectLater(
        repo.listAllFlats(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INTERNAL_ERROR'),
        ),
      );
    });

    test('caches full list until force refresh', () async {
      var calls = 0;
      final adapter = ScriptedAdapter((options) async {
        calls++;
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_flat(0)],
            'pagination': {
              'page': 1,
              'limit': 100,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.society.listAllFlats();
      await repos.society.listAllFlats();
      expect(calls, 1);
      await repos.society.listAllFlats(force: true);
      expect(calls, 2);
    });
  });

  group('AnnouncementFlatPickerModel', () {
    FlatSummary f(int i, {String? wing}) => FlatSummary(
          id: _flatId(i),
          societyId: societyId,
          wingId: wingId,
          wingCode: wing ?? 'A',
          wingName: 'Wing ${wing ?? 'A'}',
          number: 'F-$i',
          floor: i ~/ 10,
          position: i % 10,
          flatType: '2BHK',
          maintenanceRate: 1000,
          isActive: true,
          occupancyStatus: 'OWNER_OCCUPIED',
          createdAt: '2026-10-20T10:00:00.000Z',
          updatedAt: '2026-10-20T10:00:00.000Z',
        );

    test('selects flats across display pages without duplicates', () {
      final model = AnnouncementFlatPickerModel(pageSize: 20);
      model.replaceFlats([for (var i = 0; i < 140; i++) f(i)]);
      expect(model.totalPages, 7);

      model.setSelected(_flatId(0), true);
      model.goToPage(2);
      model.setSelected(_flatId(25), true);
      model.goToPage(7);
      model.setSelected(_flatId(139), true);
      // Duplicate select is a no-op for the set.
      expect(model.setSelected(_flatId(0), true), isFalse);

      expect(model.selectedIds, {
        _flatId(0),
        _flatId(25),
        _flatId(139),
      });
      expect(model.selectedIds, hasLength(3));
    });

    test('search filters across all loaded flats and resets page', () {
      final model = AnnouncementFlatPickerModel(pageSize: 20)
        ..replaceFlats([
          for (var i = 0; i < 50; i++) f(i, wing: i < 25 ? 'A' : 'B'),
        ]);
      model.goToPage(2);
      model.setSelected(_flatId(30), true);

      model.setSearch('wing b');
      expect(model.page, 1);
      expect(model.totalFiltered, 25);
      expect(model.pageItems.every((x) => x.wingCode == 'B'), isTrue);
      // Selection preserved after search.
      expect(model.isSelected(_flatId(30)), isTrue);

      model.setSearch('F-7');
      expect(model.filtered.map((x) => x.number), contains('F-7'));
      expect(model.isSelected(_flatId(30)), isTrue);
    });

    test('preserves selections after clearing search / changing page', () {
      final model = AnnouncementFlatPickerModel(
        initiallySelected: {_flatId(5)},
        pageSize: 10,
      )..replaceFlats([for (var i = 0; i < 40; i++) f(i)]);

      model.setSelected(_flatId(15), true);
      model.setSearch('F-1');
      model.goToPage(2);
      model.setSearch('');
      expect(model.selectedIds, {_flatId(5), _flatId(15)});
      expect(model.page, 1);
    });

    test('flat labels include wing and number', () {
      expect(
        announcementFlatLabel(f(12, wing: 'C')),
        'C-F-12',
      );
    });

    test('deselect removes only that id', () {
      final model = AnnouncementFlatPickerModel(
        initiallySelected: {_flatId(1), _flatId(2)},
      );
      model.setSelected(_flatId(1), false);
      expect(model.selectedIds, {_flatId(2)});
    });
  });
}

const societyId = '507f1f77bcf86cd799439011';
const wingId = '507f1f77bcf86cd799439012';

String _flatId(int i) =>
    '507f1f77bcf86cd79943${(1000 + i).toString().padLeft(4, '0')}';

Map<String, Object?> _flat(int i) => {
      'id': _flatId(i),
      'societyId': societyId,
      'wingId': wingId,
      'wingCode': 'A',
      'wingName': 'Wing A',
      'number': 'F-$i',
      'floor': i ~/ 10,
      'position': i % 10,
      'flatType': '2BHK',
      'maintenanceRate': 1000,
      'isActive': true,
      'occupancyStatus': 'OWNER_OCCUPIED',
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
    };

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
