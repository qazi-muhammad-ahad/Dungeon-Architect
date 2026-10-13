import 'dart:math' as math;

import 'package:flutter/material.dart';

/// All units are logical pixels; device-pixel ratio never enters hit testing.
class CanvasCamera {
  double scale = 4;
  Offset origin = Offset.zero;
  Offset toWorld(Offset point) => (point - origin) / scale;
  Offset toScreen(Offset point) => origin + point * scale;
  Point<int>? tileAt(Offset point, int columns, int rows) {
    final p = toWorld(point),
        x = toWorld(point).dx.floor(),
        y = toWorld(point).dy.floor();
    return p.dx < 0 || p.dy < 0 || x >= columns || y >= rows
        ? null
        : Point(x, y);
  }

  void fit(Size viewport, int columns, int rows) {
    scale = math.max(
      .25,
      math.min((viewport.width - 48) / columns, (viewport.height - 48) / rows),
    );
    origin = Offset(
      (viewport.width - columns * scale) / 2,
      (viewport.height - rows * scale) / 2,
    );
  }

  void zoom(Offset anchor, double factor) {
    final world = toWorld(anchor);
    scale = (scale * factor).clamp(.25, 64);
    origin = anchor - world * scale;
  }

  void pan(Offset delta) => origin += delta;
  Rect visible(Size viewport, int columns, int rows) {
    final a = toWorld(Offset.zero),
        b = toWorld(viewport.bottomRight(Offset.zero));
    return Rect.fromLTRB(
      a.dx.floor().clamp(0, columns).toDouble(),
      a.dy.floor().clamp(0, rows).toDouble(),
      b.dx.ceil().clamp(0, columns).toDouble(),
      b.dy.ceil().clamp(0, rows).toDouble(),
    );
  }
}

// Interpolation belongs to pointer input, not mask-domain rules.
Iterable<Point<int>> strokeLine(Point<int> a, Point<int> b) sync* {
  var x = a.x, y = a.y;
  final dx = (b.x - x).abs(),
      dy = -(b.y - y).abs(),
      sx = x < b.x ? 1 : -1,
      sy = y < b.y ? 1 : -1;
  var error = dx + dy;
  while (true) {
    yield Point(x, y);
    if (x == b.x && y == b.y) break;
    final twice = 2 * error;
    if (twice >= dy) {
      error += dy;
      x += sx;
    }
    if (twice <= dx) {
      error += dx;
      y += sy;
    }
  }
}

typedef Point<T extends num> = math.Point<T>;
