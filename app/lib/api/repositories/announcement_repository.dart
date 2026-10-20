import '../models/announcement_models.dart';
import '../models/common.dart';
import '../models/notification_models.dart';
import '../services/announcement_api.dart';

/// Cached announcement reads and guarded mutations.
class AnnouncementRepository {
  AnnouncementRepository(this._api);

  final AnnouncementApi _api;

  Paged<Announcement>? lastAdminList;
  String? lastAdminListKey;
  Paged<Announcement>? lastResidentList;
  String? lastResidentListKey;
  AnnouncementSummary? lastSummary;
  UnreadCount? lastUnreadCount;
  final Map<String, Announcement> _byId = {};
  final Map<String, AnnouncementRecipientSummary> _recipients = {};

  bool mutationLocked = false;

  void clear() {
    lastAdminList = null;
    lastAdminListKey = null;
    lastResidentList = null;
    lastResidentListKey = null;
    lastSummary = null;
    lastUnreadCount = null;
    _byId.clear();
    _recipients.clear();
    mutationLocked = false;
  }

  void invalidateCaches({String? announcementId}) {
    lastAdminList = null;
    lastAdminListKey = null;
    lastResidentList = null;
    lastResidentListKey = null;
    lastSummary = null;
    lastUnreadCount = null;
    if (announcementId != null) {
      _byId.remove(announcementId);
      _recipients.remove(announcementId);
    } else {
      _byId.clear();
      _recipients.clear();
    }
  }

  Future<T> _locked<T>(Future<T> Function() run) async {
    if (mutationLocked) {
      throw StateError('An announcement action is already in progress.');
    }
    mutationLocked = true;
    try {
      return await run();
    } finally {
      mutationLocked = false;
    }
  }

  void _store(Announcement a) => _byId[a.id] = a;

  Future<AnnouncementSummary> summary({bool force = false}) async {
    if (!force && lastSummary != null) return lastSummary!;
    final s = await _api.summary();
    lastSummary = s;
    return s;
  }

  Future<Paged<Announcement>> listAdmin({
    ListAdminAnnouncementsQuery query = const ListAdminAnnouncementsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastAdminList != null && lastAdminListKey == key) {
      return lastAdminList!;
    }
    final page = await _api.listAdmin(query: query);
    lastAdminList = page;
    lastAdminListKey = key;
    for (final a in page.items) {
      _store(a);
    }
    return page;
  }

  Future<Announcement> getAdmin(String id, {bool force = false}) async {
    if (!force && _byId.containsKey(id)) return _byId[id]!;
    final a = await _api.getAdmin(id);
    _store(a);
    return a;
  }

  Future<Announcement> create(CreateAnnouncementRequest request) {
    return _locked(() async {
      final a = await _api.create(request);
      invalidateCaches();
      _store(a);
      return a;
    });
  }

  Future<Announcement> update(String id, UpdateAnnouncementRequest request) {
    return _locked(() async {
      final a = await _api.update(id, request);
      invalidateCaches(announcementId: id);
      _store(a);
      return a;
    });
  }

  Future<Announcement> publish(String id) {
    return _locked(() async {
      final a = await _api.publish(id);
      invalidateCaches(announcementId: id);
      _store(a);
      return a;
    });
  }

  Future<Announcement> schedule(String id, {required String scheduledAt}) {
    return _locked(() async {
      final a = await _api.schedule(id, scheduledAt: scheduledAt);
      invalidateCaches(announcementId: id);
      _store(a);
      return a;
    });
  }

  Future<Announcement> cancel(String id) {
    return _locked(() async {
      final a = await _api.cancel(id);
      invalidateCaches(announcementId: id);
      _store(a);
      return a;
    });
  }

  Future<Announcement> archive(String id) {
    return _locked(() async {
      final a = await _api.archive(id);
      invalidateCaches(announcementId: id);
      _store(a);
      return a;
    });
  }

  Future<AnnouncementRecipientSummary> recipients(
    String id, {
    bool force = false,
  }) async {
    if (!force && _recipients.containsKey(id)) return _recipients[id]!;
    final s = await _api.recipients(id);
    _recipients[id] = s;
    return s;
  }

  Future<AnnouncementAttachmentUploadResult> uploadAttachment(
    String announcementId, {
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) {
    return _locked(() async {
      final result = await _api.uploadAttachment(
        announcementId,
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
      invalidateCaches(announcementId: announcementId);
      _store(result.announcement);
      return result;
    });
  }

  Future<Announcement> removeAttachment(
    String announcementId,
    String attachmentId,
  ) {
    return _locked(() async {
      final a = await _api.removeAttachment(announcementId, attachmentId);
      invalidateCaches(announcementId: announcementId);
      _store(a);
      return a;
    });
  }

  Future<List<int>> downloadAdminAttachment(
    String announcementId,
    String attachmentId,
  ) {
    return _api.downloadAdminAttachment(announcementId, attachmentId);
  }

  Future<UnreadCount> unreadCount({bool force = false}) async {
    if (!force && lastUnreadCount != null) return lastUnreadCount!;
    final c = await _api.unreadCount();
    lastUnreadCount = c;
    return c;
  }

  Future<Paged<Announcement>> listResident({
    ListResidentAnnouncementsQuery query =
        const ListResidentAnnouncementsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastResidentList != null && lastResidentListKey == key) {
      return lastResidentList!;
    }
    final page = await _api.listResident(query: query);
    lastResidentList = page;
    lastResidentListKey = key;
    for (final a in page.items) {
      _store(a);
    }
    return page;
  }

  Future<Announcement> getResident(String id, {bool force = false}) async {
    if (!force && _byId.containsKey(id) && _byId[id]!.isRead != null) {
      return _byId[id]!;
    }
    final a = await _api.getResident(id);
    _store(a);
    return a;
  }

  Future<AnnouncementReadState> markRead(String id) {
    return _locked(() async {
      final state = await _api.markRead(id);
      invalidateCaches(announcementId: id);
      return state;
    });
  }

  Future<AnnouncementReadState> markUnread(String id) {
    return _locked(() async {
      final state = await _api.markUnread(id);
      invalidateCaches(announcementId: id);
      return state;
    });
  }

  Future<List<int>> downloadResidentAttachment(
    String announcementId,
    String attachmentId,
  ) {
    return _api.downloadResidentAttachment(announcementId, attachmentId);
  }
}
