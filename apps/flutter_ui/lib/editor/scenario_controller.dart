import 'package:flutter/foundation.dart';

import '../engine/engine.dart';
import 'exact_json.dart';

class ScenarioController extends ChangeNotifier {
  ScenarioController(this.engine);
  final Engine Function() engine;
  EngineResult? baseline, result;
  int baselineJob = 0, revision = -1, version = 0;
  bool busy = false, stale = false, blocking = false;
  bool _disposed = false;
  String message =
      'Temporary scenarios preserve the saved baseline. Full exact allocation reruns.';
  final Set<String> blocked = {}, disabled = {};
  final Map<String, int> capacities = {};
  BigInt? budget;
  Map<String, dynamic>? get payload =>
      (result ?? baseline)?.document['result'] as Map<String, dynamic>?;
  Map<String, dynamic>? get displayPayload =>
      payload == null ? null : {...payload!, if (stale) 'allocation': null};
  Map<String, dynamic> get metadata =>
      result?.document['scenario'] as Map<String, dynamic>? ?? {};
  bool get changed =>
      blocked.isNotEmpty ||
      disabled.isNotEmpty ||
      capacities.isNotEmpty ||
      budget != null;
  bool get exitReachable => !stale && metadata['exit_reachable'] != false;
  int get snapshotJob =>
      result == null ? baselineJob : metadata['snapshot_job'] as int;
  void bind(EngineResult? current, int stamp, int job) {
    if (identical(current, baseline) && revision == stamp) {
      return;
    }
    baseline = current;
    baselineJob = job;
    revision = stamp;
    result = null;
    blocked.clear();
    disabled.clear();
    capacities.clear();
    budget = null;
    stale = false;
    version++;
  }

  void edit() {
    version++;
    stale = true;
    notifyListeners();
  }

  void toggleTile(int x, int y) {
    final key = '$x,$y';
    if (!blocked.add(key)) {
      blocked.remove(key);
    }
    edit();
  }

  void reset() {
    version++;
    blocked.clear();
    disabled.clear();
    capacities.clear();
    budget = null;
    result = null;
    stale = false;
    message = 'Baseline restored. Saved source is unchanged.';
    notifyListeners();
  }

  Future<void> apply() async {
    if (_disposed || busy || baseline == null) {
      return;
    }
    final stamp = version;
    busy = true;
    stale = true;
    notifyListeners();
    try {
      final next = await engine().run(
        encodeExact({
          'baseline_job': baselineJob,
          'blocked_tiles': blocked
              .map((key) => key.split(',').map(int.parse).toList())
              .toList(),
          'disabled_rooms': disabled.toList(),
          'capacities': capacities,
          if (budget != null) 'budget': budget,
        }),
        operation: EngineOperation.scenario,
        maxEvents: 256,
      );
      if (_disposed || stamp != version) {
        return;
      }
      if (next.succeeded) {
        result = next;
        stale = false;
        message = exitReachable
            ? 'Scenario verified. Full exact allocation rerun completed.'
            : 'Exit disconnected from entrance. Restore a route before starting Play.';
      } else {
        final diagnostics = next.document['diagnostics'] as List? ?? [];
        message = diagnostics.isEmpty
            ? '${next.document['outcome']}'
            : '${diagnostics.first['message']} ${diagnostics.first['recovery']}';
      }
    } catch (error) {
      if (!_disposed && stamp == version) {
        message = '$error';
      }
    } finally {
      busy = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    version++;
    super.dispose();
  }
}
