// Actual Dart web adapter exercised from the Chrome integration harness.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import '../../apps/flutter_ui/lib/engine/engine.dart';

@JS('runDartProbe')
external set registerProbe(JSFunction value);

Future<JSString> probe(JSString small, JSString large) async {
  final engine = Engine();
  var checks = 0;
  void check(bool condition, String label) {
    if (!condition) throw StateError(label);
    checks++;
  }
  var ticks = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
  try {
    final unused = Engine();
    await unused.close();
    check(unused.closed, 'close before open');
    try { await unused.open(); throw StateError('Expected closed rejection'); }
    on EngineException catch (error) { check(error.code == 'closed', 'closed cannot reopen'); }
    await engine.open();
    final baseline = await engine.run(small.toDart, maxEvents: 16);
    check(baseline.succeeded, 'Dart receives successful C++ result');
    check((await engine.metrics()).containsKey('allocation'), 'metrics');
    final trace = await engine.trace(count: 3);
    check((trace['events'] as List).length <= 3, 'bounded trace');
    final marker = baseline.document['result']['geometry']['entrance_marker'];
    final moved = await engine.step(snapshotJob: engine.snapshotJob,
        x: marker['x'] as int, y: marker['y'] as int, dx: 1, dy: 0);
    check(moved.containsKey('x'), 'authoritative simulation');
    final bad = await engine.run('{');
    check(!bad.succeeded && identical(engine.lastResult, baseline), 'failed result preservation');
    final before = ticks;
    final running = engine.run(large.toDart);
    // Wait for actual native work, then request cooperative cancellation.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (engine.progress.state != 1 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await engine.cancel();
    final cancelled = await running;
    check(cancelled.document['outcome'] == 'cancelled', 'cancellation');
    check(identical(engine.lastResult, baseline), 'cancel preserves last result');
    check(ticks > before, 'UI event loop responsive during native work');
    try { await engine.trace(count: 129); throw StateError('Expected trace rejection'); }
    on EngineException catch (error) { check(error.code == 'invalid_argument', 'structured errors'); }
    final again = await engine.run(small.toDart, maxEvents: 16);
    check(again.rawJson == baseline.rawJson, 'repeat determinism');
    await engine.close();
    check(engine.closed, 'close');
    return jsonEncode({'checks': checks, 'ticks': ticks}).toJS;
  } finally { timer.cancel(); await engine.close(); }
}
void main() { registerProbe = ((JSString small, JSString large) => probe(small,large).toJS).toJS; }
