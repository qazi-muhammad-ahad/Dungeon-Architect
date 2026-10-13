import 'dart:convert';

// Transport codec only. C++ still validates all schema/domain rules. BigInt keeps
// imported int64 fields exact when a different field is edited on Dart web.
dynamic decodeExact(String raw) {
  var marker = '__da_integer__';
  while (raw.contains(marker)) {
    marker += '_';
  }
  final output = StringBuffer();
  var quoted = false, escaped = false;
  for (var i = 0; i < raw.length; i++) {
    final char = raw[i];
    if (quoted) {
      output.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        quoted = false;
      }
    } else if (char == '"') {
      quoted = true;
      output.write(char);
    } else if (char == '-' || RegExp(r'[0-9]').hasMatch(char)) {
      final begin = i;
      while (i + 1 < raw.length &&
          RegExp(r'[0-9eE+.\-]').hasMatch(raw[i + 1])) {
        i++;
      }
      final token = raw.substring(begin, i + 1);
      final number = BigInt.tryParse(token);
      output.write(
        number != null && number.abs() > BigInt.from(9007199254740991)
            ? jsonEncode('$marker$token')
            : token,
      );
    } else {
      output.write(char);
    }
  }
  return jsonDecode(
    output.toString(),
    reviver: (key, value) => value is String && value.startsWith(marker)
        ? BigInt.parse(value.substring(marker.length))
        : value,
  );
}

String encodeExact(dynamic value) {
  if (value is BigInt) return value.toString();
  if (value is Map) {
    return '{${value.entries.map((e) => '${jsonEncode(e.key)}:${encodeExact(e.value)}').join(',')}}';
  }
  if (value is List) return '[${value.map(encodeExact).join(',')}]';
  return jsonEncode(value);
}
