import '../models/resident_models.dart';
import '../services/resident_api.dart';

/// Cached resident profile and flat membership reads.
class ResidentRepository {
  ResidentRepository(this._api);

  final ResidentApi _api;

  ResidentProfile? _profile;
  Future<ResidentProfile>? _profileInFlight;

  List<ResidentFlat>? _flats;
  Future<List<ResidentFlat>>? _flatsInFlight;

  final Map<String, ResidentFlat> _flatById = {};
  final Map<String, Future<ResidentFlat>> _flatInFlight = {};

  void clear() {
    _profile = null;
    _profileInFlight = null;
    _flats = null;
    _flatsInFlight = null;
    _flatById.clear();
    _flatInFlight.clear();
  }

  ResidentProfile? get cachedProfile => _profile;
  List<ResidentFlat>? get cachedFlats =>
      _flats == null ? null : List.unmodifiable(_flats!);

  Future<ResidentProfile> profile({bool force = false}) {
    if (!force && _profile != null) {
      return Future<ResidentProfile>.value(_profile!);
    }
    if (!force && _profileInFlight != null) return _profileInFlight!;
    final future = _api.profile().then((value) {
      _profile = value;
      return value;
    });
    _profileInFlight = future;
    return future.whenComplete(() {
      if (identical(_profileInFlight, future)) _profileInFlight = null;
    });
  }

  Future<List<ResidentFlat>> flats({bool force = false}) {
    if (!force && _flats != null) {
      return Future<List<ResidentFlat>>.value(_flats!);
    }
    if (!force && _flatsInFlight != null) return _flatsInFlight!;
    final future = _api.flats().then((value) {
      _flats = value;
      for (final item in value) {
        _flatById[item.flat.id] = item;
      }
      return value;
    });
    _flatsInFlight = future;
    return future.whenComplete(() {
      if (identical(_flatsInFlight, future)) _flatsInFlight = null;
    });
  }

  Future<ResidentFlat> flat(String flatId, {bool force = false}) {
    if (!force && _flatById.containsKey(flatId)) {
      return Future<ResidentFlat>.value(_flatById[flatId]!);
    }
    final existing = _flatInFlight[flatId];
    if (!force && existing != null) return existing;
    final future = _api.flat(flatId).then((value) {
      _flatById[flatId] = value;
      return value;
    });
    _flatInFlight[flatId] = future;
    return future.whenComplete(() {
      if (identical(_flatInFlight[flatId], future)) {
        _flatInFlight.remove(flatId);
      }
    });
  }

  /// Seeds cache from an already-loaded session context (avoids a duplicate GET).
  void seedFromSession({
    ResidentProfile? profile,
    List<ResidentFlat>? flats,
  }) {
    if (profile != null) _profile = profile;
    if (flats != null) {
      _flats = List.of(flats);
      for (final item in flats) {
        _flatById[item.flat.id] = item;
      }
    }
  }
}
