import 'dart:convert';
import 'dart:typed_data';

import 'package:apna_society/api/apna_api.dart';
import 'package:apna_society/api/config/api_config.dart';
import 'package:apna_society/api/http/api_client.dart';
import 'package:apna_society/api/http/api_exception.dart';
import 'package:apna_society/api/models/announcement_models.dart';
import 'package:apna_society/api/models/notification_models.dart';
import 'package:apna_society/api/repositories/announcement_repository.dart';
import 'package:apna_society/api/repositories/live_repositories.dart';
import 'package:apna_society/api/repositories/notification_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(clearLiveRepositories);

  group('Announcement DTO parsing', () {
    test('parses admin announcement with admin-only fields', () {
      final a = Announcement.fromJson(_announcement(admin: true));
      expect(a.status, 'DRAFT');
      expect(a.audienceType, 'ALL_RESIDENTS');
      expect(a.audienceRole, 'ALL');
      expect(a.adminNotes, 'Internal');
      expect(a.deliveryState, 'NOT_STARTED');
      expect(a.targetWingIds, isEmpty);
    });

    test('parses resident announcement without inventing admin fields', () {
      final a = Announcement.fromJson(_announcement(admin: false, isRead: false));
      expect(a.isRead, isFalse);
      expect(a.adminNotes, isNull);
      expect(a.deliveryState, isNull);
      expect(a.targetWingIds, isNull);
    });

    test('parses recipient summary', () {
      final s = AnnouncementRecipientSummary.fromJson({
        'announcementId': announcementId,
        'status': 'PUBLISHED',
        'deliveryState': 'COMPLETE',
        'eligibleRecipientCount': 12,
        'notificationCreatedCount': 12,
        'readCount': 4,
        'note': 'persistence count',
      });
      expect(s.readCount, 4);
    });

    test('parses socket announcement event', () {
      final e = AnnouncementEventPayload.fromJson({
        'announcementId': announcementId,
        'societyId': societyId,
        'title': 'Water cut',
        'category': 'WATER_SUPPLY',
        'priority': 'IMPORTANT',
        'publishedAt': '2026-10-20T10:00:00.000Z',
      });
      expect(e.announcementId, announcementId);
    });
  });

  group('Admin announcements', () {
    test('creates draft with audience', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/admin/announcements'), isTrue);
        expect(options.data['audienceType'], 'WING');
        expect(options.data['audienceRole'], 'OWNERS');
        expect(options.data['targetWingIds'], [wingId]);
        expect(options.method, 'POST');
        return jsonBody(201, {
          'success': true,
          'data': _announcement(
            admin: true,
            audienceType: 'WING',
            targetWingIds: [wingId],
          ),
        });
      });
      final repo = AnnouncementRepository(_api(adapter).announcements);
      final created = await repo.create(
        const CreateAnnouncementRequest(
          title: 'Wing notice',
          body: 'Please note elevator maintenance',
          category: 'MAINTENANCE',
          audienceType: 'WING',
          audienceRole: 'OWNERS',
          targetWingIds: [wingId],
        ),
      );
      expect(created.status, 'DRAFT');
      expect(created.audienceType, 'WING');
    });

    test('updates draft only path', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.method, 'PATCH');
        return jsonBody(200, {
          'success': true,
          'data': _announcement(admin: true, title: 'Updated'),
        });
      });
      final repo = AnnouncementRepository(_api(adapter).announcements);
      final updated = await repo.update(
        announcementId,
        const UpdateAnnouncementRequest(title: 'Updated'),
      );
      expect(updated.title, 'Updated');
    });

    test('publish and schedule paths', () async {
      final paths = <String>[];
      final adapter = ScriptedAdapter((options) async {
        paths.add(options.path);
        if (options.path.endsWith('/publish')) {
          return jsonBody(200, {
            'success': true,
            'data': _announcement(admin: true, status: 'PUBLISHED'),
          });
        }
        return jsonBody(200, {
          'success': true,
          'data': _announcement(admin: true, status: 'SCHEDULED'),
        });
      });
      final repo = AnnouncementRepository(_api(adapter).announcements);
      final published = await repo.publish(announcementId);
      expect(published.status, 'PUBLISHED');
      final scheduled = await repo.schedule(
        announcementId,
        scheduledAt: '2099-01-01T10:00:00.000Z',
      );
      expect(scheduled.status, 'SCHEDULED');
      expect(paths.any((p) => p.endsWith('/publish')), isTrue);
      expect(paths.any((p) => p.endsWith('/schedule')), isTrue);
    });

    test('not editable surfaces ANNOUNCEMENT_NOT_EDITABLE', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(409, {
          'success': false,
          'error': {
            'code': 'ANNOUNCEMENT_NOT_EDITABLE',
            'message': 'Only draft',
          },
        });
      });
      final repo = AnnouncementRepository(_api(adapter).announcements);
      await expectLater(
        repo.update(
          announcementId,
          const UpdateAnnouncementRequest(title: 'Nope'),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'ANNOUNCEMENT_NOT_EDITABLE'),
        ),
      );
    });

    test('attachment upload request path', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/attachments'), isTrue);
        expect(options.data, isA<FormData>());
        return jsonBody(200, {
          'success': true,
          'data': {
            'announcement': _announcement(admin: true),
            'attachment': {
              'id': attachmentId,
              'mimeType': 'image/jpeg',
              'sizeBytes': 1200,
            },
          },
        });
      });
      final repo = AnnouncementRepository(_api(adapter).announcements);
      final result = await repo.uploadAttachment(
        announcementId,
        bytes: [1, 2, 3],
        filename: 'notice.jpg',
        mimeType: 'image/jpeg',
      );
      expect(result.attachmentId, attachmentId);
    });
  });

  group('Resident announcements', () {
    test('lists feed with pagination and isRead', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.contains('/resident/announcements'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [
              _announcement(admin: false, isRead: false, status: 'PUBLISHED'),
            ],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = AnnouncementRepository(_api(adapter).announcements);
      final page = await repo.listResident();
      expect(page.items.first.isRead, isFalse);
    });

    test('mark read returns state', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/read'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {'isRead': true},
        });
      });
      final repo = AnnouncementRepository(_api(adapter).announcements);
      final state = await repo.markRead(announcementId);
      expect(state.isRead, isTrue);
    });

    test('unread count', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.path.endsWith('/unread-count'), isTrue);
        return jsonBody(200, {
          'success': true,
          'data': {'unreadCount': 3},
        });
      });
      final repo = AnnouncementRepository(_api(adapter).announcements);
      final c = await repo.unreadCount();
      expect(c.unreadCount, 3);
    });

    test('attachment download path', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(
          options.path.endsWith(
            '/announcements/$announcementId/attachments/$attachmentId',
          ),
          isTrue,
        );
        return ResponseBody.fromBytes(
          Uint8List.fromList([9, 8, 7]),
          200,
          headers: {
            Headers.contentTypeHeader: ['image/jpeg'],
          },
        );
      });
      final repo = AnnouncementRepository(_api(adapter).announcements);
      final bytes = await repo.downloadResidentAttachment(
        announcementId,
        attachmentId,
      );
      expect(bytes, [9, 8, 7]);
    });
  });

  group('Notifications', () {
    test('parses notification and unknown type safely', () {
      final n = AppNotification.fromJson(_notification());
      expect(n.type, 'ANNOUNCEMENT');
      expect(n.isKnownType, isTrue);
      expect(
        AppNotification.fromJson(_notification(type: 'BILL_OVERDUE')).isKnownType,
        isTrue,
      );
      expect(
        notificationTypeLabel('BILL_OVERDUE'),
        contains('Overdue'),
      );
      final unknown = AppNotification.fromJson(
        _notification(type: 'FUTURE_TYPE'),
      );
      expect(unknown.isKnownType, isFalse);
      expect(notificationTypeLabel(unknown.type), 'Notification');
    });

    test('lists with pagination and unread filter', () async {
      final adapter = ScriptedAdapter((options) async {
        expect(options.queryParameters['isRead'], 'false');
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_notification()],
            'pagination': {
              'page': 1,
              'limit': 20,
              'total': 1,
              'totalPages': 1,
            },
          },
        });
      });
      final repo = NotificationRepository(_api(adapter).notifications);
      final page = await repo.list(
        query: const ListNotificationsQuery(isRead: false),
      );
      expect(page.items, hasLength(1));
    });

    test('mark one and mark all read', () async {
      final adapter = ScriptedAdapter((options) async {
        if (options.path.endsWith('/read-all')) {
          return jsonBody(200, {
            'success': true,
            'data': {'updated': 5},
          });
        }
        return jsonBody(200, {
          'success': true,
          'data': _notification(isRead: true),
        });
      });
      final repo = NotificationRepository(_api(adapter).notifications);
      final one = await repo.markRead(notificationId);
      expect(one.isRead, isTrue);
      final all = await repo.markAllRead();
      expect(all.updated, 5);
    });

    test('403 access denied', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(403, {
          'success': false,
          'error': {
            'code': 'NOTIFICATION_ACCESS_DENIED',
            'message': 'Denied',
          },
        });
      });
      final repo = NotificationRepository(_api(adapter).notifications);
      await expectLater(
        repo.get(notificationId),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'NOTIFICATION_ACCESS_DENIED'),
        ),
      );
    });

    test('parses socket notification event', () {
      final e = NotificationEventPayload.fromJson({
        'id': notificationId,
        'societyId': societyId,
        'recipientUserId': userId,
        'type': 'ANNOUNCEMENT',
        'title': 'New',
        'body': 'Body',
        'isRead': false,
        'createdAt': '2026-10-20T10:00:00.000Z',
        'relatedEntityId': announcementId,
        'relatedEntityType': 'Announcement',
      });
      expect(e.relatedEntityId, announcementId);
    });
  });

  group('Cache and logout', () {
    test('announcement mutation invalidates list cache', () async {
      var calls = 0;
      final adapter = ScriptedAdapter((options) async {
        calls++;
        if (options.path.endsWith('/publish')) {
          return jsonBody(200, {
            'success': true,
            'data': _announcement(admin: true, status: 'PUBLISHED'),
          });
        }
        return jsonBody(200, {
          'success': true,
          'data': {
            'items': [_announcement(admin: true)],
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
      await repos.announcements.listAdmin();
      await repos.announcements.listAdmin();
      expect(calls, 1);
      await repos.announcements.publish(announcementId);
      await repos.announcements.listAdmin();
      expect(calls, greaterThan(2));
    });

    test('notification cache cleared on LiveRepositories.clear', () async {
      final adapter = ScriptedAdapter((options) async {
        return jsonBody(200, {
          'success': true,
          'data': {'unreadCount': 2},
        });
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.notifications.unreadCount();
      expect(repos.notifications.lastUnreadCount?.unreadCount, 2);
      clearLiveRepositories();
      expect(liveRepositories, isNull);
    });

    test('socket-style invalidation refreshes unread', () async {
      var calls = 0;
      final adapter = ScriptedAdapter((options) async {
        calls++;
        return jsonBody(200, {
          'success': true,
          'data': {'unreadCount': calls},
        });
      });
      final repos = ensureLiveRepositories(_api(adapter));
      await repos.notifications.unreadCount();
      repos.invalidateAfterNotificationMutation(notificationId: notificationId);
      final next = await repos.notifications.unreadCount();
      expect(next.unreadCount, 2);
    });
  });
}

const societyId = '507f1f77bcf86cd799439011';
const announcementId = '507f1f77bcf86cd7994390c1';
const attachmentId = '507f1f77bcf86cd7994390c2';
const notificationId = '507f1f77bcf86cd7994390c3';
const wingId = '507f1f77bcf86cd7994390c4';
const userId = '507f1f77bcf86cd799439021';

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

Map<String, Object?> _announcement({
  required bool admin,
  String status = 'DRAFT',
  String audienceType = 'ALL_RESIDENTS',
  List<String> targetWingIds = const [],
  String title = 'Notice',
  bool? isRead,
}) =>
    {
      'id': announcementId,
      'societyId': societyId,
      'title': title,
      'body': 'Please note elevator maintenance this weekend',
      'category': 'MAINTENANCE',
      'priority': 'NORMAL',
      'audienceType': audienceType,
      if (admin) 'targetWingIds': targetWingIds,
      if (admin) 'targetFlatIds': <String>[],
      'attachments': <Map<String, Object?>>[],
      'status': status,
      if (admin) 'deliveryState': 'NOT_STARTED',
      if (admin) 'createdBy': userId,
      if (admin) 'adminNotes': 'Internal',
      if (isRead != null) 'isRead': isRead,
      'createdAt': '2026-10-20T10:00:00.000Z',
      'updatedAt': '2026-10-20T10:00:00.000Z',
    };

Map<String, Object?> _notification({
  String type = 'ANNOUNCEMENT',
  bool isRead = false,
}) =>
    {
      'id': notificationId,
      'societyId': societyId,
      'recipientUserId': userId,
      'type': type,
      'title': 'New announcement',
      'body': 'Water supply notice',
      'relatedEntityType': 'Announcement',
      'relatedEntityId': announcementId,
      'isRead': isRead,
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
