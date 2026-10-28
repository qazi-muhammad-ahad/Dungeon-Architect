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

  void pause() {
    paused = true;
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
    if (paused || completed || snapshot == null || held.isEmpty) {
      return;
    }
    _elapsed = (_elapsed + delta.inMicroseconds.clamp(0, 1000000) / 1000000)
        .clamp(0, 1);
    if (moving) {
      return;
    }
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
        x = position['x'] as int;
        y = position['y'] as int;
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
      }
    } finally {
      moving = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Map<String, dynamic>? nearbyActor() {
    for (final actor in snapshot?['allocation']?['actors'] as List? ?? []) {
      final tile = actor['tile'];
      if ((x - (tile['x'] as int)).abs() + (y - (tile['y'] as int)).abs() <=
          2) {
        return Map<String, dynamic>.from(actor as Map);
      }
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    held.clear();
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
