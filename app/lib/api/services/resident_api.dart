import '../config/api_config.dart';
import '../http/api_client.dart';
import '../http/api_exception.dart';
import '../models/resident_models.dart';

/// Resident profile and flat access under `/api/v1/resident`.
class ResidentApi {
  ResidentApi(this._client);
  final ApiClient _client;

  static const _root = '${ApiConfig.apiPrefix}/resident';

  Future<ResidentProfile> profile({String? societyId}) {
    return _client.get(
      '$_root/profile',
      societyId: societyId,
      decode: ResidentProfile.fromJson,
    );
  }

  Future<List<ResidentFlat>> flats({String? societyId}) {
    return _client.get(
      '$_root/flats',
      societyId: societyId,
      decode: (data) {
        if (data is! List) {
          throw ApiParseException('Expected flat list');
        }
        return data.map(ResidentFlat.fromJson).toList();
      },
    );
  }

  Future<ResidentFlat> flat(String flatId, {String? societyId}) {
    return _client.get(
      '$_root/flats/$flatId',
      societyId: societyId,
      decode: ResidentFlat.fromJson,
    );
  }

  Future<ResidentOccupancy> occupancy(String flatId, {String? societyId}) {
    return _client.get(
      '$_root/flats/$flatId/occupancy',
      societyId: societyId,
      decode: ResidentOccupancy.fromJson,
    );
  }
}
