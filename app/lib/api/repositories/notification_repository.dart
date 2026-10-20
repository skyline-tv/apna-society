import '../models/common.dart';
import '../models/notification_models.dart';
import '../services/notification_api.dart';

/// Cached resident notification inbox.
class NotificationRepository {
  NotificationRepository(this._api);

  final NotificationApi _api;

  Paged<AppNotification>? lastList;
  String? lastListKey;
  UnreadCount? lastUnreadCount;
  final Map<String, AppNotification> _byId = {};

  bool mutationLocked = false;

  void clear() {
    lastList = null;
    lastListKey = null;
    lastUnreadCount = null;
    _byId.clear();
    mutationLocked = false;
  }

  void invalidateCaches({String? notificationId}) {
    lastList = null;
    lastListKey = null;
    lastUnreadCount = null;
    if (notificationId != null) {
      _byId.remove(notificationId);
    } else {
      _byId.clear();
    }
  }

  Future<T> _locked<T>(Future<T> Function() run) async {
    if (mutationLocked) {
      throw StateError('A notification action is already in progress.');
    }
    mutationLocked = true;
    try {
      return await run();
    } finally {
      mutationLocked = false;
    }
  }

  Future<UnreadCount> unreadCount({bool force = false}) async {
    if (!force && lastUnreadCount != null) return lastUnreadCount!;
    final c = await _api.unreadCount();
    lastUnreadCount = c;
    return c;
  }

  Future<Paged<AppNotification>> list({
    ListNotificationsQuery query = const ListNotificationsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastList != null && lastListKey == key) {
      return lastList!;
    }
    final page = await _api.list(
      isRead: query.isRead,
      type: query.type,
      page: query.page,
      limit: query.limit,
    );
    lastList = page;
    lastListKey = key;
    for (final n in page.items) {
      _byId[n.id] = n;
    }
    return page;
  }

  Future<AppNotification> get(String id, {bool force = false}) async {
    if (!force && _byId.containsKey(id)) return _byId[id]!;
    final n = await _api.get(id);
    _byId[n.id] = n;
    return n;
  }

  Future<AppNotification> markRead(String id) {
    return _locked(() async {
      final n = await _api.markRead(id);
      invalidateCaches(notificationId: id);
      _byId[n.id] = n;
      return n;
    });
  }

  Future<AppNotification> markUnread(String id) {
    return _locked(() async {
      final n = await _api.markUnread(id);
      invalidateCaches(notificationId: id);
      _byId[n.id] = n;
      return n;
    });
  }

  Future<MarkAllReadResult> markAllRead() {
    return _locked(() async {
      final result = await _api.markAllRead();
      invalidateCaches();
      return result;
    });
  }
}
