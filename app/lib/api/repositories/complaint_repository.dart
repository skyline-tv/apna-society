import '../models/common.dart';
import '../models/complaint_models.dart';
import '../services/complaint_api.dart';

/// Cached complaint reads and guarded mutations.
class ComplaintRepository {
  ComplaintRepository(this._api);

  final ComplaintApi _api;

  Paged<Complaint>? lastResidentList;
  String? lastResidentListKey;
  Paged<Complaint>? lastAdminList;
  String? lastAdminListKey;
  ComplaintSummary? lastSummary;
  List<String>? lastCategories;
  final Map<String, Complaint> _byId = {};

  bool mutationLocked = false;

  void clear() {
    lastResidentList = null;
    lastResidentListKey = null;
    lastAdminList = null;
    lastAdminListKey = null;
    lastSummary = null;
    lastCategories = null;
    _byId.clear();
    mutationLocked = false;
  }

  void invalidateCaches({String? complaintId}) {
    lastResidentList = null;
    lastResidentListKey = null;
    lastAdminList = null;
    lastAdminListKey = null;
    lastSummary = null;
    if (complaintId != null) {
      _byId.remove(complaintId);
    } else {
      _byId.clear();
    }
  }

  Future<T> _locked<T>(Future<T> Function() run) async {
    if (mutationLocked) {
      throw StateError('A complaint action is already in progress.');
    }
    mutationLocked = true;
    try {
      return await run();
    } finally {
      mutationLocked = false;
    }
  }

  void _store(Complaint c) => _byId[c.id] = c;

  Future<Paged<Complaint>> listResident({
    ListComplaintsQuery query = const ListComplaintsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastResidentList != null && lastResidentListKey == key) {
      return lastResidentList!;
    }
    final page = await _api.listResident(query: query);
    lastResidentList = page;
    lastResidentListKey = key;
    for (final c in page.items) {
      _store(c);
    }
    return page;
  }

  Future<Complaint> getResident(String id, {bool force = false}) async {
    if (!force && _byId.containsKey(id) && _byId[id]!.history.isNotEmpty) {
      return _byId[id]!;
    }
    final c = await _api.getResident(id);
    _store(c);
    return c;
  }

  Future<Complaint> create(CreateComplaintRequest request) {
    return _locked(() async {
      final c = await _api.create(request);
      invalidateCaches();
      _store(c);
      return c;
    });
  }

  Future<Complaint> cancelResident(String id, {String? reason}) {
    return _locked(() async {
      final c = await _api.cancelResident(id, reason: reason);
      invalidateCaches(complaintId: id);
      _store(c);
      return c;
    });
  }

  Future<ComplaintAttachmentUploadResult> uploadResidentAttachment(
    String complaintId, {
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) {
    return _locked(() async {
      final result = await _api.uploadResidentAttachment(
        complaintId,
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
      invalidateCaches(complaintId: complaintId);
      _store(result.complaint);
      return result;
    });
  }

  Future<List<int>> downloadResidentAttachment(
    String complaintId,
    String attachmentId,
  ) {
    return _api.downloadResidentAttachment(complaintId, attachmentId);
  }

  Future<List<String>> categories({bool force = false}) async {
    if (!force && lastCategories != null) return lastCategories!;
    final items = await _api.categories();
    lastCategories = items;
    return items;
  }

  Future<ComplaintSummary> summary({bool force = false}) async {
    if (!force && lastSummary != null) return lastSummary!;
    final s = await _api.summary();
    lastSummary = s;
    return s;
  }

  Future<Paged<Complaint>> listAdmin({
    ListComplaintsQuery query = const ListComplaintsQuery(),
    bool force = false,
  }) async {
    final key = query.toQuery().values.join('|');
    if (!force && lastAdminList != null && lastAdminListKey == key) {
      return lastAdminList!;
    }
    final page = await _api.listAdmin(query: query);
    lastAdminList = page;
    lastAdminListKey = key;
    for (final c in page.items) {
      _store(c);
    }
    return page;
  }

  Future<Complaint> getAdmin(String id, {bool force = false}) async {
    if (!force && _byId.containsKey(id) && _byId[id]!.history.isNotEmpty) {
      return _byId[id]!;
    }
    final c = await _api.getAdmin(id);
    _store(c);
    return c;
  }

  Future<Complaint> updatePriority(String id, {required String priority}) {
    return _locked(() async {
      final c = await _api.updatePriority(id, priority: priority);
      invalidateCaches(complaintId: id);
      _store(c);
      return c;
    });
  }

  Future<Complaint> assign(
    String id, {
    required String assignmentType,
    String? assignedToUserId,
    ExternalAssignee? externalAssignee,
    String? notes,
  }) {
    return _locked(() async {
      final c = await _api.assign(
        id,
        assignmentType: assignmentType,
        assignedToUserId: assignedToUserId,
        externalAssignee: externalAssignee,
        notes: notes,
      );
      invalidateCaches(complaintId: id);
      _store(c);
      return c;
    });
  }

  Future<Complaint> unassign(String id, {String? reason}) {
    return _locked(() async {
      final c = await _api.unassign(id, reason: reason);
      invalidateCaches(complaintId: id);
      _store(c);
      return c;
    });
  }

  Future<Complaint> start(String id) {
    return _locked(() async {
      final c = await _api.start(id);
      invalidateCaches(complaintId: id);
      _store(c);
      return c;
    });
  }

  Future<Complaint> resolve(
    String id, {
    required String resolutionNotes,
    String? internalNotes,
  }) {
    return _locked(() async {
      final c = await _api.resolve(
        id,
        resolutionNotes: resolutionNotes,
        internalNotes: internalNotes,
      );
      invalidateCaches(complaintId: id);
      _store(c);
      return c;
    });
  }

  Future<Complaint> close(String id) {
    return _locked(() async {
      final c = await _api.close(id);
      invalidateCaches(complaintId: id);
      _store(c);
      return c;
    });
  }

  Future<Complaint> cancelAdmin(String id, {required String reason}) {
    return _locked(() async {
      final c = await _api.cancelAdmin(id, reason: reason);
      invalidateCaches(complaintId: id);
      _store(c);
      return c;
    });
  }

  Future<ComplaintAttachmentUploadResult> uploadAdminAttachment(
    String complaintId, {
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) {
    return _locked(() async {
      final result = await _api.uploadAdminAttachment(
        complaintId,
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
      invalidateCaches(complaintId: complaintId);
      _store(result.complaint);
      return result;
    });
  }

  Future<List<int>> downloadAdminAttachment(
    String complaintId,
    String attachmentId,
  ) {
    return _api.downloadAdminAttachment(complaintId, attachmentId);
  }
}
