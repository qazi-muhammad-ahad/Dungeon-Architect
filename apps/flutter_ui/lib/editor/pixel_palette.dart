import 'package:flutter/material.dart';

/// Original, code-native pixel motifs. Geometry and collision remain native.
class DungeonPixels {
  static const voidColor = Color(0xff20252b);
  static const floor = Color(0xff69796f);
  static const floorLight = Color(0xff819084);
  static const wall = Color(0xff414e58);
  static const wallLight = Color(0xff8a979d);
  static const door = Color(0xffdab675);
  static const entrance = Color(0xff83dbad);
  static const exit = Color(0xffd0b6ff);
  static const encounter = Color(0xffffd18b);

  // Snap shared tile edges in device space, without changing world hit testing.
  static Rect snap(Rect r, double dpr) => Rect.fromLTRB(
    (r.left * dpr).round() / dpr,
    (r.top * dpr).round() / dpr,
    (r.right * dpr).round() / dpr,
    (r.bottom * dpr).round() / dpr,
  );

  static void motif(Canvas canvas, Rect r, String kind, double dpr) {
    final paint = Paint()..isAntiAlias = false;
    void block(double x, double y, double w, double h, Color color) {
      paint.color = color;
      canvas.drawRect(
        snap(
          Rect.fromLTWH(
            r.left + x * r.width / 8,
            r.top + y * r.height / 8,
            w * r.width / 8,
            h * r.height / 8,
          ),
          dpr,
        ),
        paint,
      );
    }

    switch (kind) {
      case 'floor':
        if (r.width >= 8) {
          block(1, 1, 2, 1, floorLight);
          block(5, 6, 2, 1, floorLight);
        }
      case 'wall':
        if (r.width >= 8) {
          block(0, 0, 8, 1, wallLight);
          block(3, 1, 1, 3, voidColor);
          block(0, 4, 8, 1, voidColor);
          block(6, 5, 1, 3, voidColor);
        }
      case 'door':
        block(0, 0, 8, 8, wall);
        block(1, 1, 6, 6, door);
        block(2, 3, 4, 2, voidColor);
      case 'entrance':
        block(1, 1, 6, 6, voidColor);
        block(2, 1, 4, 1, entrance);
        block(1, 2, 1, 5, entrance);
        block(6, 2, 1, 5, entrance);
      case 'exit':
        block(1, 1, 6, 6, voidColor);
        block(1, 5, 6, 2, exit);
        block(3, 3, 4, 2, exit);
        block(5, 1, 2, 2, exit);
      case 'encounter':
        block(3, 1, 2, 6, voidColor);
        block(1, 3, 6, 2, voidColor);
        block(3, 2, 2, 4, encounter);
        block(2, 3, 4, 2, encounter);
      case 'player':
        block(2, 0, 4, 8, voidColor);
        block(1, 2, 6, 5, voidColor);
        block(3, 1, 2, 2, Colors.white);
        block(2, 3, 4, 3, Colors.white);
        block(2, 6, 1, 1, Colors.white);
        block(5, 6, 1, 1, Colors.white);
    }
  }
}
