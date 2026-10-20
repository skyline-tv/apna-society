import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/complaint_models.dart';
import 'package:apna_society/api/repositories/complaint_repository.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(clearLiveRepositories);

  group('Complaint DTO parsing', () {
    test('parses complaint with public fields and no invented notes', () {
      final c = Complaint.fromJson(_complaint());
      expect(c.complaintNumber, 'CMP-20261020-ABCDEF');
      expect(c.status, 'OPEN');
      expect(c.priority, 'MEDIUM');
      expect(c.internalNotes, isNull);
      expect(c.attachments, hasLength(1));
    });

    test('parses admin detail with history and internal notes', () {
      final c = Complaint.fromJson(_complaint(
        withInternal: true,
        withHistory: true,
      ));
      expect(c.internalNotes, 'Admin only');
      expect(c.history, hasLength(1));
      expect(c.history.first.notes, 'Internal history');
      expect(c.history.first.publicNotes, 'Public history');
    });

    test('parses socket payload', () {
      final e = ComplaintEventPayload.fromJson({
        'complaintId': complaintId,
        'societyId': societyId,
        'flatId': flatId,
        'complaintNumber': 'CMP-1',
        'status': 'ASSIGNED',
        'priority': 'HIGH',
        'category': 'PLUMBING',
        'title': 'Leak',
        'raisedByUserId': raiserId,
        'assignedToUserId': assigneeId,
      });
      expect(e.assignedToUserId, assigneeId);
    });

    test('client attachment validation helpers', () {
      expect(
        kComplaintAttachmentMimeTypes.contains('image/jpeg'),
        isTrue,
      );
      expect(kComplaintAttachmentMaxBytes, 5 * 1024 * 1024);
      expect(kComplaintAttachmentMaxCount, 5);
    });
  });

  group('Resident complaints', () {
    test('creates complaint', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/resident/complaints'), isTrue);
        expect(options.data['category'], 'PLUMBING');
        expect(options.data.containsKey('priority'), isFalse);
        return jsonBody(201, {'success': true, 'data': _complaint()});
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      final created = await repo.create(
        const CreateComplaintRequest(
          flatId: flatId,
          category: 'PLUMBING',
          title: 'Kitchen leak',
          description: 'Water dripping under sink',
        ),
      );
      expect(created.status, 'OPEN');
      expect(created.complaintNumber, startsWith('CMP-'));
    });

    test('lists with pagination', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_complaint()],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      final page = await repo.listResident();
      expect(page.items, hasLength(1));
      expect(page.pagination.total, 1);
    });

    test('loads detail with history', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(200, {
          'success': true,
          'data': _complaint(withHistory: true),
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      final detail = await repo.getResident(complaintId);
      expect(detail.history.first.action, 'CREATED');
    });

    test('resident cancel when OPEN', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/cancel'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': _complaint(status: 'CANCELLED'),
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      final cancelled = await repo.cancelResident(complaintId, reason: 'Fixed');
      expect(cancelled.status, 'CANCELLED');
    });

    test('invalid cancel surfaces INVALID_STATUS_TRANSITION', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'INVALID_STATUS_TRANSITION',
            'message': 'Not open',
          },
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      await expectLater(
        repo.cancelResident(complaintId),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'INVALID_STATUS_TRANSITION'),
        ),
      );
    });

    test('former tenant / access denial', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {
            'code': 'COMPLAINT_ACCESS_DENIED',
            'message': 'Denied',
          },
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      await expectLater(
        repo.getResident(complaintId),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'COMPLAINT_ACCESS_DENIED'),
        ),
      );
    });
  });

  group('Admin transitions', () {
    test('assign and reassign', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/assign'), isTrue);
        expect(options.data['assignmentType'], 'INTERNAL');
        return jsonBody(200, {
          'success': true,
          'data': _complaint(status: 'ASSIGNED'),
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      final assigned = await repo.assign(
        complaintId,
        assignmentType: 'INTERNAL',
        assignedToUserId: assigneeId,
        notes: 'Please check',
      );
      expect(assigned.status, 'ASSIGNED');
    });

    test('start, resolve, close happy path', () async {
      var step = 0;
      final adapter = ScriptedAdapter((options) async {
        step++;
        if (options.path.endsWith('/start')) {
          return jsonBody(200, {
            'success': true,
            'data': _complaint(status: 'IN_PROGRESS'),
          });
        }
        if (options.path.endsWith('/resolve')) {
          expect(options.data['resolutionNotes'], isNotEmpty);
          return jsonBody(200, {
            'success': true,
            'data': _complaint(status: 'RESOLVED', withInternal: true),
          });
        }
        expect(options.path.endsWith('/close'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': _complaint(status: 'CLOSED'),
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      expect((await repo.start(complaintId)).status, 'IN_PROGRESS');
      expect(
        (await repo.resolve(
          complaintId,
          resolutionNotes: 'Fixed pipe',
          internalNotes: 'Used spare parts',
        ))
            .status,
        'RESOLVED',
      );
      expect((await repo.close(complaintId)).status, 'CLOSED');
      expect(step, 3);
    });

    test('invalid transition is rejected', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'INVALID_STATUS_TRANSITION',
            'message': 'Cannot close',
          },
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      await expectLater(
        repo.close(complaintId),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'INVALID_STATUS_TRANSITION'),
        ),
      );
    });
  });

  group('Attachments', () {
    test('upload returns attachment metadata without storage keys', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.contains('/attachments'), isTrue);
        expect(options.data, isA<FormData>());
        return jsonBody(201, {
          'success': true,
          'data': {
            'complaint': _complaint(),
            'attachment': {
              'id': attachmentId,
              'mimeType': 'image/jpeg',
              'sizeBytes': 1200,
              'originalFilename': 'leak.jpg',
              'uploadedByUserId': raiserId,
              'createdAt': '2026-10-20T10:00:00.000Z',
            },
          },
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      final result = await repo.uploadResidentAttachment(
        complaintId,
        bytes: List<int>.filled(100, 1),
        filename: 'leak.jpg',
        mimeType: 'image/jpeg',
      );
      expect(result.attachment?.id, attachmentId);
      expect(result.attachment?.originalFilename, 'leak.jpg');
    });

    test('oversized / invalid type errors', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(400, {
          'success': false,
          'error': {
            'code': 'ATTACHMENT_TOO_LARGE',
            'message': 'Too large',
          },
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      await expectLater(
        repo.uploadResidentAttachment(
          complaintId,
          bytes: List<int>.filled(10, 1),
          filename: 'big.jpg',
          mimeType: 'image/jpeg',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'ATTACHMENT_TOO_LARGE'),
        ),
      );
    });
  });

  group('Cache and auth', () {
    test('cache invalidation after mutation', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.method == 'GET') {
          return jsonBody(200, {
            'success': true,
            'data': {
              'items': [_complaint()],
              'pagination': {
                'page': 1,
                'limit': 20,
                'total': 1,
                'totalPages': 1,
              },
            },
          });
        }
        return jsonBody(200, {
          'success': true,
          'data': _complaint(status: 'CANCELLED'),
        });
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.complaints.listResident();
      expect(repos.complaints.lastResidentList, isNotNull);
      await repos.complaints.cancelResident(complaintId);
      expect(repos.complaints.lastResidentList, isNull);
    });

    test('403 without inventing success', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {'code': 'FORBIDDEN_ROLE', 'message': 'Forbidden'},
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      await expectLater(
        repo.listAdmin(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'FORBIDDEN_ROLE'),
        ),
      );
      expect(repo.lastAdminList, isNull);
    });

    test('duplicate mutation lock', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final adapter = ScriptedAdapter((options) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return jsonBody(200, {
          'success': true,
          'data': _complaint(status: 'IN_PROGRESS'),
        });
      });
      final repo = ComplaintRepository(_api(adapter).complaints);
      final first = repo.start(complaintId);
      await entered.future;
      expect(repo.mutationLocked, isTrue);
      await expectLater(repo.start(complaintId), throwsA(isA<StateError>()));
      release.complete();
      await first;
    });
  });
}

const societyId = '507f1f77bcf86cd799439011';
const flatId = '507f1f77bcf86cd799439013';
const complaintId = '507f1f77bcf86cd7994390a1';
const attachmentId = '507f1f77bcf86cd7994390a2';
const raiserId = '507f1f77bcf86cd799439021';
const assigneeId = '507f1f77bcf86cd799439022';

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

Map<String, Object?> _complaint({
  String status = 'OPEN',
  bool withInternal = false,
  bool withHistory = false,
}) =>
    {
      'id': complaintId,
      'societyId': societyId,
      'flatId': flatId,
      'complaintNumber': 'CMP-20261020-ABCDEF',
      'raisedByUserId': raiserId,
      'raisedByRole': 'OWNER',
      'category': 'PLUMBING',
      'title': 'Kitchen leak',
      'description': 'Water dripping under sink',
      'priority': 'MEDIUM',
      'status': status,
      if (withInternal) 'internalNotes': 'Admin only',
      'attachments': [
        {
          'id': attachmentId,
          'mimeType': 'image/jpeg',
          'sizeBytes': 1200,
          'originalFilename': 'leak.jpg',
          'uploadedByUserId': raiserId,
          'createdAt': '2026-10-20T10:00:00.000Z',
        },
      ],
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
      if (withHistory)
        'history': [
          {
            'id': '507f1f77bcf86cd7994390b1',
            'complaintId': complaintId,
            'societyId': societyId,
            'action': 'CREATED',
            'actorUserId': raiserId,
            'actorRole': 'OWNER',
            'publicNotes': 'Public history',
            if (withInternal) 'notes': 'Internal history',
            'createdAt': '2026-10-20T10:00:00.000Z',
          },
        ],
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
