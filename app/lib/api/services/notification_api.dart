import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/json_read.dart';
import '../models/common.dart';
import '../models/notification_models.dart';

/// Resident notification inbox under `/api/v1/resident/notifications`.
class NotificationApi {
  NotificationApi(this._client);
  final ApiClient _client;

  static const _root = '${ApiConfig.apiPrefix}/me/notifications';

  Future<UnreadCount> unreadCount({String? societyId}) {
    return _client.get(
      '$_root/unread-count',
      societyId: societyId,
      decode: UnreadCount.fromJson,
    );
  }

  Future<MarkAllReadResult> markAllRead({String? societyId}) {
    return _client.post(
      '$_root/read-all',
      societyId: societyId,
      decode: MarkAllReadResult.fromJson,
    );
  }

  Future<Paged<AppNotification>> list({
    bool? isRead,
    String? type,
    int? page,
    int? limit,
    String? societyId,
  }) {
    return _client.get(
      _root,
      query: omitNulls({
        'isRead': isRead == null ? null : (isRead ? 'true' : 'false'),
        'type': type,
        'page': page,
        'limit': limit,
      }),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, AppNotification.fromJson),
    );
  }

  Future<AppNotification> get(String notificationId, {String? societyId}) {
    return _client.get(
      '$_root/$notificationId',
      societyId: societyId,
      decode: AppNotification.fromJson,
    );
  }

  Future<AppNotification> markRead(String notificationId, {String? societyId}) {
    return _client.post(
      '$_root/$notificationId/read',
      societyId: societyId,
      decode: AppNotification.fromJson,
    );
  }

  Future<AppNotification> markUnread(String notificationId, {String? societyId}) {
    return _client.post(
      '$_root/$notificationId/unread',
      societyId: societyId,
      decode: AppNotification.fromJson,
    );
  }
}
