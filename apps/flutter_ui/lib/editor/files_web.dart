import 'dart:convert';
import 'dart:js_interop';

@JS('DungeonFiles')
extension type _Files._(JSObject _) implements JSObject {
  external factory _Files();
  external JSPromise<JSString> open();
  external JSPromise<JSString> save(String text, String name, bool saveAs);
  external void adopt();
  external void reset();
  external void setDirty(bool value);
  external void dispose();
}

class ProjectFiles {
  final _files = _Files();
  Future<Map<String, dynamic>?> open() async =>
      jsonDecode((await _files.open().toDart).toDart) as Map<String, dynamic>?;
  Future<Map<String, dynamic>> save(
    String raw,
    String name,
    bool saveAs,
  ) async =>
      jsonDecode((await _files.save(raw, name, saveAs).toDart).toDart)
          as Map<String, dynamic>;
  void adopt() => _files.adopt();
  void reset() => _files.reset();
  void setDirty(bool value) => _files.setDirty(value);
  void dispose() => _files.dispose();
}
