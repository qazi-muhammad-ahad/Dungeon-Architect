import 'dart:convert';
import 'dart:js_interop';

import 'models.dart';

@JS('DungeonEngineClient')
extension type _Client._(JSObject _) implements JSObject {
  external factory _Client();
  external JSPromise<JSAny?> get ready;
  external JSPromise<JSString> run(
    String project,
    int operation,
    int events,
    int flags,
  );
  external JSPromise<JSAny?> cancel();
  external JSPromise<JSAny?> close();
  external JSPromise<JSString> metrics();
  external JSPromise<JSString> trace(int cursor, int count);
  external JSPromise<JSString> step(
    int snapshotJob,
    int x,
    int y,
    int dx,
    int dy,
  );
  external String get progressJson;
  external int get snapshotJob;
  external bool get closed;
  external static String safeJson(String raw);
  external static String get environmentJson;
}

@JS()
extension type _Error._(JSObject _) implements JSObject {
  external JSString? get code;
  external JSString? get message;
}

class Engine {
  _Client? _instance;
  bool _disposed = false;
  _Client get _client {
    if (_disposed) throw const EngineException('closed', 'Engine is closed.');
    return _instance ??= _Client();
  }

  EngineResult? lastResult;
  bool get supported => true;
  Map<String,dynamic> get environment => jsonDecode(_Client.environmentJson) as Map<String,dynamic>;
  bool get closed => _disposed || (_instance?.closed ?? false);
  int get snapshotJob => _instance?.snapshotJob ?? 0;
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      if (error is EngineException) rethrow;
      if (error.isA<JSObject>()) {
        final value = _Error._(error as JSObject);
        throw EngineException(
          value.code?.toDart ?? 'engine_error',
          value.message?.toDart ?? error.toString(),
        );
      }
      throw EngineException('engine_error', error.toString());
    }
  }

  Future<void> open() => _guard(() async {
    await _client.ready.toDart;
  });
  EngineProgress get progress {
    if (_instance == null) return const EngineProgress(0, 0, 0);
    final value = jsonDecode(_client.progressJson) as Map<String, dynamic>;
    return EngineProgress(
      value['state'] as int,
      value['stage'] as int,
      value['outcome'] as int,
    );
  }

  Map<String, dynamic> _decode(String raw) =>
      jsonDecode(_Client.safeJson(raw)) as Map<String, dynamic>;

  Future<EngineResult> run(
    String project, {
    EngineOperation operation = EngineOperation.run,
    int maxEvents = 256,
    bool detailedTrace = false,
  }) => _guard(() async {
    final raw =
        (await _client
                .run(
                  project,
                  operation.index + 1,
                  maxEvents,
                  detailedTrace ? 1 : 0,
                )
                .toDart)
            .toDart;
    final result = EngineResult(raw, _decode(raw));
    if (result.succeeded &&
        ((operation.index >= 1 && operation.index <= 4) ||
            operation == EngineOperation.reallocate ||
            operation == EngineOperation.generateDungeon)) {
      lastResult = result;
    }
    return result;
  });
  Future<void> cancel() => _guard(() async {
    await _client.cancel().toDart;
  });
  Future<Map<String, dynamic>> metrics() =>
      _guard(() async => _decode((await _client.metrics().toDart).toDart));
  Future<Map<String, dynamic>> trace({int cursor = 0, int count = 128}) =>
      _guard(
        () async => _decode((await _client.trace(cursor, count).toDart).toDart),
      );
  Future<Map<String, dynamic>> step({
    required int snapshotJob,
    required int x,
    required int y,
    required int dx,
    required int dy,
  }) => _guard(
    () async =>
        _decode((await _client.step(snapshotJob, x, y, dx, dy).toDart).toDart),
  );
  Future<void> close() => _guard(() async {
    _disposed = true;
    if (_instance != null) await _instance!.close().toDart;
  });
}
