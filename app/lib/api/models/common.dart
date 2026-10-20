import '../http/json_read.dart';

/// Mongo ObjectId canonical form, matching backend `isObjectId`
/// (`Types.ObjectId.isValid` plus round-trip equality).
final objectIdPattern = RegExp(r'^[a-fA-F0-9]{24}$');

bool isObjectId(String value) => objectIdPattern.hasMatch(value);

class Page {
  const Page({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  final int page;
  final int limit;
  final int total;
  final int totalPages;

  factory Page.fromJson(JsonMap json) {
    return Page(
      page: requireInt(json, 'page'),
      limit: requireInt(json, 'limit'),
      total: requireInt(json, 'total'),
      totalPages: requireInt(json, 'totalPages'),
    );
  }
}

class Paged<T> {
  const Paged({required this.items, required this.pagination});

  final List<T> items;
  final Page pagination;

  static Paged<T> fromJson<T>(
    Object? data,
    T Function(JsonMap json) decodeItem,
  ) {
    final json = requireMap(data, 'page');
    return Paged(
      items: requireMapList(json, 'items').map(decodeItem).toList(),
      pagination: Page.fromJson(requireMap(json['pagination'], 'pagination')),
    );
  }
}

class MessageResult {
  const MessageResult({required this.message});
  final String message;

  factory MessageResult.fromJson(Object? data) {
    final json = requireMap(data, 'message');
    return MessageResult(message: requireString(json, 'message'));
  }
}

class CountResult {
  const CountResult({required this.count, required this.field});
  final int count;
  final String field;

  factory CountResult.fromJson(Object? data, String field) {
    final json = requireMap(data, field);
    return CountResult(count: requireInt(json, field), field: field);
  }
}
