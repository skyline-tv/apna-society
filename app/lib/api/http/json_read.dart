import 'api_exception.dart';

typedef JsonMap = Map<String, Object?>;

JsonMap requireMap(Object? value, String label) {
  if (value is Map) {
    return value.map((key, nested) => MapEntry(key.toString(), nested));
  }
  throw ApiParseException('Expected object for $label');
}

String requireString(JsonMap json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw ApiParseException('Expected string $key');
}

String? optionalString(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw ApiParseException('Expected string $key');
}

int requireInt(JsonMap json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw ApiParseException('Expected integer $key');
}

int? optionalInt(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  throw ApiParseException('Expected integer $key');
}

bool requireBool(JsonMap json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw ApiParseException('Expected boolean $key');
}

bool? optionalBool(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is bool) return value;
  throw ApiParseException('Expected boolean $key');
}

double? optionalDouble(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  throw ApiParseException('Expected number $key');
}

List<JsonMap> requireMapList(JsonMap json, String key) {
  final value = json[key];
  if (value is! List) {
    throw ApiParseException('Expected list $key');
  }
  return value.map((item) => requireMap(item, key)).toList();
}

Map<String, int> requireIntMap(JsonMap json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw ApiParseException('Expected object $key');
  }
  return value.map((entryKey, nested) {
    if (nested is! int) {
      throw ApiParseException('Expected integer values in $key');
    }
    return MapEntry(entryKey.toString(), nested);
  });
}

List<String> requireStringList(JsonMap json, String key) {
  final value = json[key];
  if (value is! List) {
    throw ApiParseException('Expected list $key');
  }
  return value.map((item) {
    if (item is! String) {
      throw ApiParseException('Expected string items in $key');
    }
    return item;
  }).toList();
}

JsonMap? optionalJsonMap(JsonMap json, String key) {
  final value = json[key];
  if (value == null) return null;
  return requireMap(value, key);
}

Map<String, Object?> omitNulls(Map<String, Object?> source) {
  return {
    for (final entry in source.entries)
      if (entry.value != null) entry.key: entry.value,
  };
}
