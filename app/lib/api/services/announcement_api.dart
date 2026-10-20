import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../http/api_client.dart';
import '../models/announcement_models.dart';
import '../models/common.dart';
import '../models/notification_models.dart';

/// Admin and resident announcement routes.
class AnnouncementApi {
  AnnouncementApi(this._client);
  final ApiClient _client;

  static const _admin = '${ApiConfig.apiPrefix}/admin';
  static const _resident = '${ApiConfig.apiPrefix}/resident';

  // ─── Admin ───────────────────────────────────────────────────────────────

  Future<AnnouncementSummary> summary({String? societyId}) {
    return _client.get(
      '$_admin/announcements/summary',
      societyId: societyId,
      decode: AnnouncementSummary.fromJson,
    );
  }

  Future<Paged<Announcement>> listAdmin({
    ListAdminAnnouncementsQuery query = const ListAdminAnnouncementsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/announcements',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Announcement.fromJson),
    );
  }

  Future<Announcement> create(
    CreateAnnouncementRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_admin/announcements',
      body: request.toJson(),
      societyId: societyId,
      decode: Announcement.fromJson,
    );
  }

  Future<Announcement> getAdmin(String announcementId, {String? societyId}) {
    return _client.get(
      '$_admin/announcements/$announcementId',
      societyId: societyId,
      decode: Announcement.fromJson,
    );
  }

  Future<Announcement> update(
    String announcementId,
    UpdateAnnouncementRequest request, {
    String? societyId,
  }) {
    return _client.patch(
      '$_admin/announcements/$announcementId',
      body: request.toJson(),
      societyId: societyId,
      decode: Announcement.fromJson,
    );
  }

  Future<Announcement> publish(String announcementId, {String? societyId}) {
    return _client.post(
      '$_admin/announcements/$announcementId/publish',
      societyId: societyId,
      decode: Announcement.fromJson,
    );
  }

  Future<Announcement> schedule(
    String announcementId, {
    required String scheduledAt,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/announcements/$announcementId/schedule',
      body: {'scheduledAt': scheduledAt},
      societyId: societyId,
      decode: Announcement.fromJson,
    );
  }

  Future<Announcement> cancel(String announcementId, {String? societyId}) {
    return _client.post(
      '$_admin/announcements/$announcementId/cancel',
      societyId: societyId,
      decode: Announcement.fromJson,
    );
  }

  Future<Announcement> archive(String announcementId, {String? societyId}) {
    return _client.post(
      '$_admin/announcements/$announcementId/archive',
      societyId: societyId,
      decode: Announcement.fromJson,
    );
  }

  Future<AnnouncementRecipientSummary> recipients(
    String announcementId, {
    String? societyId,
  }) {
    return _client.get(
      '$_admin/announcements/$announcementId/recipients',
      societyId: societyId,
      decode: AnnouncementRecipientSummary.fromJson,
    );
  }

  Future<AnnouncementAttachmentUploadResult> uploadAttachment(
    String announcementId, {
    required List<int> bytes,
    required String filename,
    required String mimeType,
    String? societyId,
  }) {
    return _client.postMultipart(
      '$_admin/announcements/$announcementId/attachments',
      formData: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType.parse(mimeType),
        ),
      }),
      societyId: societyId,
      decode: AnnouncementAttachmentUploadResult.fromJson,
    );
  }

  Future<Announcement> removeAttachment(
    String announcementId,
    String attachmentId, {
    String? societyId,
  }) {
    return _client.delete(
      '$_admin/announcements/$announcementId/attachments/$attachmentId',
      societyId: societyId,
      decode: Announcement.fromJson,
    );
  }

  Future<List<int>> downloadAdminAttachment(
    String announcementId,
    String attachmentId, {
    String? societyId,
  }) {
    return _client.getBytes(
      '$_admin/announcements/$announcementId/attachments/$attachmentId',
      societyId: societyId,
    );
  }

  // ─── Resident ────────────────────────────────────────────────────────────

  Future<UnreadCount> unreadCount({String? societyId}) {
    return _client.get(
      '$_resident/announcements/unread-count',
      societyId: societyId,
      decode: UnreadCount.fromJson,
    );
  }

  Future<Paged<Announcement>> listResident({
    ListResidentAnnouncementsQuery query =
        const ListResidentAnnouncementsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_resident/announcements',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Announcement.fromJson),
    );
  }

  Future<Announcement> getResident(
    String announcementId, {
    String? societyId,
  }) {
    return _client.get(
      '$_resident/announcements/$announcementId',
      societyId: societyId,
      decode: Announcement.fromJson,
    );
  }

  Future<AnnouncementReadState> markRead(
    String announcementId, {
    String? societyId,
  }) {
    return _client.post(
      '$_resident/announcements/$announcementId/read',
      societyId: societyId,
      decode: AnnouncementReadState.fromJson,
    );
  }

  Future<AnnouncementReadState> markUnread(
    String announcementId, {
    String? societyId,
  }) {
    return _client.post(
      '$_resident/announcements/$announcementId/unread',
      societyId: societyId,
      decode: AnnouncementReadState.fromJson,
    );
  }

  Future<List<int>> downloadResidentAttachment(
    String announcementId,
    String attachmentId, {
    String? societyId,
  }) {
    return _client.getBytes(
      '$_resident/announcements/$announcementId/attachments/$attachmentId',
      societyId: societyId,
    );
  }
}
