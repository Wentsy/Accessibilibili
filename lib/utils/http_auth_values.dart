/// Dio adapters may normalize Cookie into a list when reusing a request.
String cookieHeaderValue(Object? value) {
  if (value is String) return value;
  if (value is Iterable) {
    return value.whereType<String>().where((v) => v.isNotEmpty).join('; ');
  }
  return '';
}
