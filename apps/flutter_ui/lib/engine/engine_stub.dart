import 'models.dart';

class Engine {
  bool get supported => false;
  Map<String,dynamic> get environment => {"platform":"unsupported"};
  bool closed = false;
  EngineResult? get lastResult => null;
  int get snapshotJob => 0;
  EngineProgress get progress => const EngineProgress(0, 0, 0);
  Never _unsupported() => throw const EngineException(
    'unsupported_platform',
    'Use Chrome for this build. Native Dart FFI and mobile builds are deferred.',
  );
  Future<void> open() async => _unsupported();
  Future<EngineResult> run(
    String project, {
    EngineOperation operation = EngineOperation.run,
    int maxEvents = 256,
    bool detailedTrace = false,
  }) async => _unsupported();
  Future<void> cancel() async => _unsupported();
  Future<Map<String, dynamic>> metrics() async => _unsupported();
  Future<Map<String, dynamic>> trace({int cursor = 0, int count = 128}) async =>
      _unsupported();
  Future<Map<String, dynamic>> step({
    required int snapshotJob,
    required int x,
    required int y,
    required int dx,
    required int dy,
  }) async => _unsupported();
  Future<void> close() async {
    closed = true;
  }
}
