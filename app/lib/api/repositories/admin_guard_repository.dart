import '../models/admin_guard_models.dart';
import '../models/common.dart';
import '../services/admin_guard_api.dart';

/// Cached admin guard reads and guarded mutations.
class AdminGuardRepository {
  AdminGuardRepository(this._api);

  final AdminGuardApi _api;

  final Map<String, AdminGuard> _byId = {};
  Paged<AdminGuard>? lastList;
  String? lastListKey;
  bool mutationLocked = false;

  void clear() {
    _byId.clear();
    lastList = null;
    lastListKey = null;
    mutationLocked = false;
  }

  void invalidate({String? guardId}) {
    lastList = null;
    lastListKey = null;
    if (guardId != null) {
      _byId.remove(guardId);
    } else {
      _byId.clear();
    }
  }

  Future<T> _locked<T>(Future<T> Function() run) async {
    if (mutationLocked) {
      throw StateError('A guard action is already in progress.');
    }
    mutationLocked = true;
    try {
      return await run();
    } finally {
      mutationLocked = false;
    }
  }

  Future<Paged<AdminGuard>> listGuards({
    ListGuardsQuery query = const ListGuardsQuery(),
    bool force = false,
  }) async {
    final key = [
      query.search,
      query.isActive,
      query.page,
      query.limit,
    ].join('|');
    if (!force && lastList != null && lastListKey == key) {
      return lastList!;
    }
    final page = await _api.listGuards(query: query);
    lastList = page;
    lastListKey = key;
    for (final guard in page.items) {
      _byId[guard.id] = guard;
    }
    return page;
  }

  Future<AdminGuard> getGuard(String guardId, {bool force = false}) async {
    if (!force && _byId.containsKey(guardId)) return _byId[guardId]!;
    final guard = await _api.getGuard(guardId);
    _byId[guard.id] = guard;
    return guard;
  }

  Future<ProvisionGuardResult> provision(CreateGuardRequest request) {
    return _locked(() async {
      final result = await _api.provision(request);
      invalidate();
      _byId[result.guard.id] = result.guard;
      return result;
    });
  }

  Future<AdminGuard> updateGuard(String guardId, UpdateGuardRequest request) {
    return _locked(() async {
      final guard = await _api.updateGuard(guardId, request);
      invalidate(guardId: guardId);
      _byId[guard.id] = guard;
      return guard;
    });
  }

  Future<AdminGuard> deactivateGuard(String guardId, {String? reason}) {
    return _locked(() async {
      final guard = await _api.deactivateGuard(guardId, reason: reason);
      invalidate(guardId: guardId);
      _byId[guard.id] = guard;
      return guard;
    });
  }
}
