/// Returns a deeply immutable copy of a JSON-compatible object.
Map<String, Object?> copyJsonObject(Map<String, Object?> value) =>
    Map<String, Object?>.unmodifiable(
      value.map((String key, Object? item) => MapEntry<String, Object?>(key, copyJsonValue(item))),
    );

/// Returns a deeply immutable copy of a JSON-compatible value.
Object? copyJsonValue(Object? value) => switch (value) {
  null || bool() || String() || num() => value,
  List<Object?>() => List<Object?>.unmodifiable(value.map(copyJsonValue)),
  Map<String, Object?>() => copyJsonObject(value),
  _ => throw ArgumentError.value(value, 'value', 'must contain only JSON-compatible values'),
};
