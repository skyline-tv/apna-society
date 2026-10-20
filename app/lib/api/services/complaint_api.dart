import 'package:dio/dio.dart';

import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/json_read.dart';
import '../models/common.dart';
import '../models/complaint_models.dart';

/// Resident and admin complaint routes.
class ComplaintApi {
  ComplaintApi(this._client);
  final ApiClient _client;

  static const _admin = '${ApiConfig.apiPrefix}/admin';
  static const _resident = '${ApiConfig.apiPrefix}/resident';

  // ─── Resident ────────────────────────────────────────────────────────────

  Future<Complaint> create(
    CreateComplaintRequest request, {
    String? societyId,
  }) {
    return _client.post(
      '$_resident/complaints',
      body: request.toJson(),
      societyId: societyId,
      decode: Complaint.fromJson,
    );
  }

  Future<Paged<Complaint>> listResident({
    ListComplaintsQuery query = const ListComplaintsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_resident/complaints',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Complaint.fromJson),
    );
  }

  Future<Complaint> getResident(String complaintId, {String? societyId}) {
    return _client.get(
      '$_resident/complaints/$complaintId',
      societyId: societyId,
      decode: Complaint.fromJson,
    );
  }

  Future<Complaint> cancelResident(
    String complaintId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_resident/complaints/$complaintId/cancel',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: Complaint.fromJson,
    );
  }

  Future<ComplaintAttachmentUploadResult> uploadResidentAttachment(
    String complaintId, {
    required List<int> bytes,
    required String filename,
    required String mimeType,
    String? societyId,
  }) {
    return _client.postMultipart(
      '$_resident/complaints/$complaintId/attachments',
      formData: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType.parse(mimeType),
        ),
      }),
      societyId: societyId,
      decode: ComplaintAttachmentUploadResult.fromJson,
    );
  }

  Future<List<int>> downloadResidentAttachment(
    String complaintId,
    String attachmentId, {
    String? societyId,
  }) {
    return _client.getBytes(
      '$_resident/complaints/$complaintId/attachments/$attachmentId',
      societyId: societyId,
    );
  }

  // ─── Admin ───────────────────────────────────────────────────────────────

  Future<List<String>> categories({String? societyId}) {
    return _client.get(
      '$_admin/complaints/categories',
      societyId: societyId,
      decode: (data) {
        final json = requireMap(data, 'categories');
        return requireStringList(json, 'items');
      },
    );
  }

  Future<ComplaintSummary> summary({
    String? from,
    String? to,
    String? societyId,
  }) {
    return _client.get(
      '$_admin/complaints/summary',
      query: omitNulls({'from': from, 'to': to}),
      societyId: societyId,
      decode: ComplaintSummary.fromJson,
    );
  }

  Future<Paged<Complaint>> listAdmin({
    ListComplaintsQuery query = const ListComplaintsQuery(),
    String? societyId,
  }) {
    return _client.get(
      '$_admin/complaints',
      query: query.toQuery(),
      societyId: societyId,
      decode: (data) => Paged.fromJson(data, Complaint.fromJson),
    );
  }

  Future<Complaint> getAdmin(String complaintId, {String? societyId}) {
    return _client.get(
      '$_admin/complaints/$complaintId',
      societyId: societyId,
      decode: Complaint.fromJson,
    );
  }

  Future<Complaint> updatePriority(
    String complaintId, {
    required String priority,
    String? societyId,
  }) {
    return _client.patch(
      '$_admin/complaints/$complaintId/priority',
      body: {'priority': priority},
      societyId: societyId,
      decode: Complaint.fromJson,
    );
  }

  Future<Complaint> assign(
    String complaintId, {
    required String assignmentType,
    String? assignedToUserId,
    ExternalAssignee? externalAssignee,
    String? notes,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/complaints/$complaintId/assign',
      body: omitNulls({
        'assignmentType': assignmentType,
        'assignedToUserId': assignedToUserId,
        'externalAssignee': externalAssignee?.toJson(),
        'notes': notes,
      }),
      societyId: societyId,
      decode: Complaint.fromJson,
    );
  }

  Future<Complaint> unassign(
    String complaintId, {
    String? reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/complaints/$complaintId/unassign',
      body: omitNulls({'reason': reason}),
      societyId: societyId,
      decode: Complaint.fromJson,
    );
  }

  Future<Complaint> start(String complaintId, {String? societyId}) {
    return _client.post(
      '$_admin/complaints/$complaintId/start',
      societyId: societyId,
      decode: Complaint.fromJson,
    );
  }

  Future<Complaint> resolve(
    String complaintId, {
    required String resolutionNotes,
    String? internalNotes,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/complaints/$complaintId/resolve',
      body: omitNulls({
        'resolutionNotes': resolutionNotes,
        'internalNotes': internalNotes,
      }),
      societyId: societyId,
      decode: Complaint.fromJson,
    );
  }

  Future<Complaint> close(String complaintId, {String? societyId}) {
    return _client.post(
      '$_admin/complaints/$complaintId/close',
      societyId: societyId,
      decode: Complaint.fromJson,
    );
  }

  Future<Complaint> cancelAdmin(
    String complaintId, {
    required String reason,
    String? societyId,
  }) {
    return _client.post(
      '$_admin/complaints/$complaintId/cancel',
      body: {'reason': reason.trim()},
      societyId: societyId,
      decode: Complaint.fromJson,
    );
  }

  Future<ComplaintAttachmentUploadResult> uploadAdminAttachment(
    String complaintId, {
    required List<int> bytes,
    required String filename,
    required String mimeType,
    String? societyId,
  }) {
    return _client.postMultipart(
      '$_admin/complaints/$complaintId/attachments',
      formData: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType.parse(mimeType),
        ),
      }),
      societyId: societyId,
      decode: ComplaintAttachmentUploadResult.fromJson,
    );
  }

  Future<List<int>> downloadAdminAttachment(
    String complaintId,
    String attachmentId, {
    String? societyId,
  }) {
    return _client.getBytes(
      '$_admin/complaints/$complaintId/attachments/$attachmentId',
      societyId: societyId,
    );
  }
}
