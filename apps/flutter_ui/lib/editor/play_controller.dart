import 'package:flutter/foundation.dart';

import 'exact_json.dart';

typedef NativeStep = Future<Map<String, dynamic>> Function({
  required int snapshotJob,
  required int x,
  required int y,
  required int dx,
  required int dy,
});

/// An immutable result plus its native identity. Every move is one native tile
/// step, serialized even when a frame takes a long time or the worker is busy.
class PlayController extends ChangeNotifier {
  PlayController(this.step);
  final NativeStep step;
  final ValueNotifier<(double, double)> motion = ValueNotifier((0.0, 0.0));
  final List<(double, double)> _approvedMotion = [];
  Map<String, dynamic>? snapshot;
  int job = 0, revision = -1, x = 0, y = 0;
  bool paused = true, completed = false, moving = false;
  String message = 'Start an exploration session.';
  final List<String> held = [];
  double _elapsed = 0;
  int _epoch = 0;
  bool _disposed = false;
  bool get active => snapshot != null;
  void start(
    Map<String, dynamic> payload,
    int snapshotJob,
    int sourceRevision,
  ) {
    _epoch++;
    snapshot =
        _freeze(decodeExact(encodeExact(payload))) as Map<String, dynamic>;
    job = snapshotJob;
    revision = sourceRevision;
    final entrance = payload['geometry']['entrance_marker'];
    x = entrance['x'] as int;
    y = entrance['y'] as int;
    _settleMotion();
    completed = false;
    paused = false;
    held.clear();
    _elapsed = 0;
    message = 'Explore with WASD or arrows. E inspects nearby encounters.';
    notifyListeners();
  }

  void restart() {
    if (snapshot != null) {
      start(snapshot!, job, revision);
    }
  }

  void _settleMotion() {
    _approvedMotion.clear();
    if (!_disposed) motion.value = (x.toDouble(), y.toDouble());
  }

  void pause() {
    paused = true;
    _settleMotion();
    held.clear();
    _elapsed = 0;
    _epoch++;
    if (!_disposed) {
      notifyListeners();
    }
  }

  void resume() {
    if (active && !completed) {
      paused = false;
      notifyListeners();
    }
  }

  void invalidate() {
    pause();
    snapshot = null;
    message = 'Session invalidated. Generate or apply the current scenario, then start again.';
    if (!_disposed) {
      notifyListeners();
    }
  }

  void key(String direction, bool down) {
    if (down && !paused && !completed) {
      if (!held.contains(direction)) {
        held.add(direction);
      }
    } else {
      held.remove(direction);
    }
    if (held.isEmpty) {
      _elapsed = 0;
    }
  }

  /// Fixed 8 tiles/s, at most 8 cardinal steps per callback. Excess suspended
  /// time is dropped; no leap or unbounded queued movement is ever submitted.
  Future<void> advance(Duration delta) async {
    _advanceMotion(delta);
    if (paused || completed || snapshot == null || held.isEmpty) {
      return;
    }
    _elapsed = (_elapsed + delta.inMicroseconds.clamp(0, 1000000) / 1000000)
        .clamp(0, 1);
    if (moving || _elapsed < .125) {
      return;
    }
    var changed = false;
    final epoch = _epoch;
    moving = true;
    try {
      var count = 0;
      while (_elapsed >= .125 &&
          count++ < 8 &&
          !paused &&
          !completed &&
          held.isNotEmpty &&
          epoch == _epoch) {
        _elapsed -= .125;
        final direction = held.last;
        final dx = direction == 'left'
            ? -1
            : direction == 'right'
            ? 1
            : 0;
        final dy = direction == 'up'
            ? -1
            : direction == 'down'
            ? 1
            : 0;
        final position = await step(
          snapshotJob: job,
          x: x,
          y: y,
          dx: dx,
          dy: dy,
        );
        if (_disposed || epoch != _epoch) {
          return;
        }
        final nextX = position['x'] as int, nextY = position['y'] as int;
        if (nextX != x || nextY != y) {
          _approvedMotion.add((nextX.toDouble(), nextY.toDouble()));
          changed = true;
        }
        x = nextX;
        y = nextY;
        final exit = snapshot!['geometry']['exit_marker'];
        completed = x == exit['x'] && y == exit['y'];
        if (completed) {
          held.clear();
          paused = true;
          message = 'Exit reached — exploration complete!';
        }
      }
      if (count >= 8) {
        _elapsed = 0;
      }
    } catch (error) {
      if (!_disposed && epoch == _epoch) {
        invalidate();
        message = 'Movement stopped: $error';
        changed = true;
      }
    } finally {
      moving = false;
      if (!_disposed && changed) {
        notifyListeners();
      }
    }
  }

  void _advanceMotion(Duration delta) {
    if (_disposed || _approvedMotion.isEmpty) return;
    var remaining = delta.inMicroseconds.clamp(0, 100000) / 1000000;
    var pose = motion.value;
    while (remaining > 0 && _approvedMotion.isNotEmpty) {
      final target = _approvedMotion.first;
      final dx = target.$1 - pose.$1, dy = target.$2 - pose.$2;
      final distance = dx.abs() + dy.abs();
      // Approved cardinal segments remain ordered even after a delayed callback.
      final secondsPerTile =
          .125 / (_approvedMotion.length > 2 ? _approvedMotion.length / 2 : 1);
      final travel = remaining / secondsPerTile;
      if (distance <= travel) {
        pose = target;
        _approvedMotion.removeAt(0);
        remaining -= distance * secondsPerTile;
      } else {
        pose = (
          pose.$1 + dx * travel / distance,
          pose.$2 + dy * travel / distance,
        );
        remaining = 0;
      }
    }
    motion.value = pose;
  }

  Map<String, dynamic>? nearbyActor() {
    Map? nearest;
    var bestDistance = 3;
    for (final actor in snapshot?['allocation']?['actors'] as List? ?? []) {
      final tile = actor['tile'];
      final distance =
          (x - (tile['x'] as int)).abs() + (y - (tile['y'] as int)).abs();
      if (distance < bestDistance) {
        nearest = actor as Map;
        bestDistance = distance;
        if (distance == 0) break;
      }
    }
    return nearest == null ? null : Map<String, dynamic>.from(nearest);
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    held.clear();
    _approvedMotion.clear();
    motion.dispose();
    super.dispose();
  }
}

dynamic _freeze(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map((key, item) => MapEntry(key as String, _freeze(item))),
    );
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(_freeze));
  }
  return value;
}
