import 'dart:js_interop';

@JS('localStorage')
external _Storage get _storage;

extension type _Storage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

bool readDarkPreference() {
  try {
    return _storage.getItem('dungeon.theme') == 'dark';
  } catch (_) {
    return false;
  }
}

void writeDarkPreference(bool value) {
  try {
    _storage.setItem('dungeon.theme', value ? 'dark' : 'light');
  } catch (_) {}
}
