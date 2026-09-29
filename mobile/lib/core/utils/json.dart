/// Small, defensive JSON helpers used by the hand-written model parsers.
library;

Map<String, dynamic> asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

Map<String, dynamic>? asJsonMapOrNull(Object? value) =>
    value is Map ? asJsonMap(value) : null;

List<dynamic> asJsonList(Object? value) =>
    value is List ? value : const <dynamic>[];

List<T> parseList<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  return asJsonList(value).whereType<Map<dynamic, dynamic>>().map((e) => parse(asJsonMap(e))).toList();
}

String asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
}

String? asStringOrNull(Object? value) {
  if (value == null) return null;
  final s = value.toString();
  return s.isEmpty ? null : s;
}

int? asIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? double.tryParse(value)?.toInt();
  }
  return null;
}

int asInt(Object? value, [int fallback = 0]) => asIntOrNull(value) ?? fallback;

DateTime? asDateOrNull(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value)?.toLocal();
  }
  if (value is DateTime) return value.toLocal();
  return null;
}

List<String> asStringList(Object? value) => asJsonList(value)
    .where((e) => e != null)
    .map((e) => e.toString())
    .toList();

String? dateToJson(DateTime? date) => date?.toUtc().toIso8601String();
