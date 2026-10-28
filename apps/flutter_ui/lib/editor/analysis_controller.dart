import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../engine/engine.dart';
import 'exact_json.dart';

dynamic _freeze(dynamic value) => value is Map
    ? Map<String, dynamic>.unmodifiable(
        value.map((key, value) => MapEntry(key as String, _freeze(value))),
      )
    : value is List
    ? List<dynamic>.unmodifiable(value.map(_freeze))
    : value;

/// Replay only reads an immutable bounded copy. It never calls the solver.
class TracePlayback extends ChangeNotifier {
  static const maxEvents = 4096;
  List<Map<String, dynamic>> events = const [];
  int cursor = 0, revision = -1, runId = 0, dropped = 0;
  bool playing = false, truncated = false;
  double speed = 4;
  Timer? _timer;
  Map<String, dynamic>? get current => cursor == 0 ? null : events[cursor - 1];
  void load(
    List<Map<String, dynamic>> value, {
    required int revision,
    required int runId,
    bool truncated = false,
    int dropped = 0,
  }) {
    pause();
    this.revision = revision;
    this.runId = runId;
    this.truncated = truncated || value.length > maxEvents;
    this.dropped = dropped + math.max(0, value.length - maxEvents);
    events = List.unmodifiable(
      value.take(maxEvents).map((e) => _freeze(e) as Map<String, dynamic>),
    );
    cursor = 0;
    notifyListeners();
  }

  void seek(int position) {
    cursor = position.clamp(0, events.length);
    if (cursor == events.length) pause();
    notifyListeners();
  }

  void step() => seek(cursor + 1);
  void restart() {
    pause();
    seek(0);
  }

  void play() {
    if (events.isEmpty || playing) return;
    if (cursor == events.length) cursor = 0;
    playing = true;
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / speed).round().clamp(16, 2000)),
      (_) => step(),
    );
    notifyListeners();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    playing = false;
    notifyListeners();
  }

  void setSpeed(double value) {
    final resume = playing;
    pause();
    speed = value.clamp(.5, 60);
    if (resume) play();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

enum BenchmarkAxis { area, rooms, packs }

class BenchmarkConfig {
  const BenchmarkConfig({
    required this.axis,
    required this.values,
    this.repeats = 3,
    this.seed = 42,
  });
  final BenchmarkAxis axis;
  final List<int> values;
  final int repeats, seed;
  int get jobs => values.length * repeats;
  void validate() {
    if (values.isEmpty ||
        values.length > 8 ||
        repeats < 2 ||
        repeats > 5 ||
        seed < 0 ||
        seed > 4294967295) {
      throw const FormatException(
        'Use 1–8 points, 2–5 repeats, and a uint32 seed.',
      );
    }
    for (final value in values) {
      final valid = switch (axis) {
        BenchmarkAxis.area =>
          value >= 4096 &&
              value <= 262144 &&
              math.sqrt(value).floor() * math.sqrt(value).floor() == value,
        BenchmarkAxis.rooms => value >= 2 && value <= 20,
        BenchmarkAxis.packs => value >= 0 && value <= 14,
      };
      if (!valid) {
        throw const FormatException(
          'Area: 4096–262144 tiles; rooms: 2–20; packs: 0–14.',
        );
      }
    }
  }

  Map<String, dynamic> get metadata => {
    'axis': axis.name,
    'values': values,
    'repeats': repeats,
    'seed': seed,
    'fixture': 'rectangle-v1; 150×150, 16 rooms, 12 packs except selected axis; 4–8 tile rooms; no fixed rooms',
  };
}

/// Controlled fixture: exactly one scaling axis varies; editor source is untouched.
String benchmarkProject(String canonical, BenchmarkConfig config, int value) {
  config.validate();
  final doc = decodeExact(canonical) as Map<String, dynamic>;
  final source = doc['source'] as Map<String, dynamic>;
  final settings = source['settings'] as Map<String, dynamic>;
  final width = config.axis == BenchmarkAxis.area
      ? math.sqrt(value).floor()
      : 150;
  final height = config.axis == BenchmarkAxis.area
      ? (value / width).ceil()
      : 150;
  settings.addAll({
    'columns': width,
    'rows': height,
    'room_count': config.axis == BenchmarkAxis.rooms ? value : 16,
    'room_width': [4, 8],
    'room_height': [4, 8],
    'margin': 1,
    'corridor_width': 1,
    'seed': config.seed,
    'max_generation_attempts': 1000,
    'max_work_units': 100000000,
    'max_time_ms': 30000,
    'threat_budget': 1000,
  });
  source['allowed_mask'] = List.filled(height, '1' * width);
  source['rooms'] = [];
  source['packs'] = List.generate(
    config.axis == BenchmarkAxis.packs ? value : 12,
    (i) => {
      'id': 'bench-${i.toString().padLeft(2, '0')}',
      'name': 'Benchmark pack $i',
      'active': true,
      'slots': 1 + (i % 3),
      'threat': 1 + (i % 5),
      'score': 1 + (i % 7),
      'min_room_width': 1,
      'min_room_height': 1,
      'allowed_roles': [],
      'required_tags': [],
    },
  );
  source['name'] = 'Controlled benchmark rectangle v1';
  return encodeExact(doc);
}

class BenchmarkController extends ChangeNotifier {
  BenchmarkController({Engine Function()? engineFactory})
    : _factory = engineFactory ?? Engine.new;
  final Engine Function() _factory;
  static const historyLimit = 60;
  final List<Map<String, dynamic>> records = [];
  Engine? _engine;
  bool running = false, cancelled = false, _disposed = false;
  int completed = 0, total = 0, batchId = 0;
  String status = 'No benchmark measurements yet.';
  BenchmarkConfig? config;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> run(String canonical, BenchmarkConfig next) async {
    if (running || _disposed) return;
    next.validate();
    batchId++;
    config = next;
    running = true;
    cancelled = false;
    completed = 0;
    total = next.jobs;
    status = 'Starting isolated benchmark worker';
    _notify();
    final engine = _factory();
    _engine = engine;
    try {
      await engine.open();
      for (final value in next.values) {
        final input = benchmarkProject(canonical, next, value);
        for (var repeat = 0; repeat < next.repeats; repeat++) {
          if (cancelled || _disposed) break;
          status =
              '${next.axis.name} $value · repeat ${repeat + 1}/${next.repeats}';
          _notify();
          final wall = Stopwatch()..start();
          final result = await engine.run(input, maxEvents: 0);
          wall.stop();
          final metrics = await engine.metrics();
          records.add({
            'batch_id': batchId,
            'batch': next.metadata,
            'axis': next.axis.name,
            'value': value,
            'repeat': repeat,
            'seed': next.seed,
            'outcome': result.document['outcome'],
            'optimal': result.document['optimal'] == true,
            'metrics': metrics,
            'bridge_wall_us': wall.elapsedMicroseconds,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'parameters': (decodeExact(input) as Map)['source']['settings'],
            'environment_note': 'Local device; worker environment/build/version in native instrumentation; no UI or playback in stage timers',
          });
          if (records.length > historyLimit) records.removeAt(0);
          completed++;
          _notify();
          await Future<void>.delayed(Duration.zero);
        }
        if (cancelled || _disposed) break;
      }
      status = cancelled
          ? 'Cancelled · $completed/$total runs retained'
          : 'Completed · $completed/$total measured runs';
    } catch (e) {
      status = 'Benchmark failed: $e';
    } finally {
      await engine.close();
      _engine = null;
      running = false;
      _notify();
    }
  }

  Future<void> cancel() async {
    cancelled = true;
    status = 'Cancelling benchmark…';
    _notify();
    await _engine?.cancel();
  }

  String get rawJson => encodeExact({
    'schema_version': 1,
    'history_limit': historyLimit,
    'records': records,
  });
  List<Map<String, dynamic>> get summary {
    final groups = <String, List<double>>{};
    for (final r in records) {
      if (r['batch_id'] != batchId || r['outcome'] != 'success') continue;
      final m = r['metrics'] as Map;
      var micros = 0.0;
      for (final stage in ['generation', 'routing', 'allocation']) {
        for (final value in (m[stage]?['timings_us'] as Map? ?? {}).values) {
          micros += (value as num).toDouble();
        }
      }
      groups
          .putIfAbsent('${r['axis']}:${r['value']}', () => [])
          .add(micros / 1000);
    }
    return groups.entries.map((g) {
      final v = g.value..sort();
      final n = v.length;
      return <String, dynamic>{
        'label': g.key,
        'n': n,
        'median_ms': n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2,
        'min_ms': v.first,
        'max_ms': v.last,
      };
    }).toList();
  }

  @override
  void dispose() {
    _disposed = true;
    cancelled = true;
    unawaited(
      (_engine?.cancel() ?? Future<void>.value()).catchError((Object _) {}),
    );
    super.dispose();
  }
}
