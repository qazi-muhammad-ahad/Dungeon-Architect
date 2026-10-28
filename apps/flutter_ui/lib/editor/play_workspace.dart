import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'project_controller.dart';

class PlayWorkspace extends StatefulWidget {
  const PlayWorkspace({super.key, required this.controller});
  final ProjectController controller;
  @override
  State<PlayWorkspace> createState() => _PlayWorkspaceState();
}

class _PlayWorkspaceState extends State<PlayWorkspace>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final focus = FocusNode(debugLabel: 'Exploration keyboard');
  late final Ticker ticker;
  Duration? previous;
  ProjectController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.play.addListener(refresh);
    ticker = createTicker((elapsed) {
      final delta = previous == null ? Duration.zero : elapsed - previous!;
      previous = elapsed;
      unawaited(c.play.advance(delta));
    })..start();
  }

  void refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      c.play.pause();
    }
  }

  Future<void> interact() async {
    final actor = c.play.nearbyActor();
    c.play.pause();
    final packs =
        c.play.snapshot?['source_project']?['source']?['packs'] as List? ??
        c.catalogue;
    final matching = packs.where((p) => p['id'] == actor?['pack_id']);
    final pack = matching.isEmpty ? null : matching.first;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          actor == null
              ? 'No nearby encounter'
              : 'Encounter ${actor['pack_id']}',
        ),
        content: Text(
          actor == null
              ? 'Move within two tiles of a static encounter marker, then press E.'
              : 'Pack: ${pack?['name'] ?? actor['pack_id']}\nRoom: ${actor['room_id']}\nThreat: ${pack?['threat'] ?? '—'}\nScore: ${pack?['score'] ?? '—'}\nStatic, nonblocking exploration marker.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  KeyEventResult key(FocusNode _, KeyEvent event) {
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.keyW || LogicalKeyboardKey.arrowUp => 'up',
      LogicalKeyboardKey.keyS || LogicalKeyboardKey.arrowDown => 'down',
      LogicalKeyboardKey.keyA || LogicalKeyboardKey.arrowLeft => 'left',
      LogicalKeyboardKey.keyD || LogicalKeyboardKey.arrowRight => 'right',
      _ => null,
    };
    if (direction != null) {
      c.play.key(direction, event is! KeyUpEvent);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyE) {
      unawaited(interact());
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      c.play.pause();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void start() {
    final payload = c.scenario.payload;
    if (payload == null) {
      return;
    }
    c.play.start(payload, c.scenario.snapshotJob, c.revision);
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = c.play, s = c.scenario;
    final available =
        c.result != null &&
        !c.stale &&
        !c.busy &&
        !s.busy &&
        !s.stale &&
        s.exitReachable &&
        s.payload?['allocation'] != null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: available ? start : null,
                child: const Text('Start exploration'),
              ),
              OutlinedButton(
                onPressed: available && p.active
                    ? () {
                        p.restart();
                        focus.requestFocus();
                      }
                    : null,
                child: const Text('Restart'),
              ),
              TextButton(
                onPressed: available && p.active && p.paused && !p.completed
                    ? () {
                        p.resume();
                        focus.requestFocus();
                      }
                    : null,
                child: const Text('Resume exploration'),
              ),
              TextButton(
                onPressed: p.active ? p.pause : null,
                child: const Text('Pause exploration'),
              ),
              TextButton(
                onPressed: p.active ? interact : null,
                child: const Text('Inspect nearby (E)'),
              ),
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  p.active
                      ? 'Player: ${p.x}, ${p.y} · ${p.completed
                            ? 'Completed'
                            : p.paused
                            ? 'Paused'
                            : 'Exploring'} · snapshot ${p.job}'
                      : 'No active exploration session',
                ),
              ),
            ],
          ),
        ),
        Text(
          !s.stale && s.metadata['exit_reachable'] == false
              ? 'Exit disconnected from entrance. Restore a route before starting Play.'
              : !available
              ? 'Generate and solve current inputs, then apply any pending scenario before Play.'
              : p.message,
        ),
        Expanded(
          child: Focus(
            focusNode: focus,
            onKeyEvent: key,
            onFocusChange: (value) {
              if (!value) {
                p.pause();
              }
            },
            child: Semantics(
              label: 'Exploration canvas',
              button: true,
              child: GestureDetector(
                onTap: () => focus.requestFocus(),
                child: ClipRect(
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: _PlayPainter(
                        p.snapshot ?? s.payload,
                        p.active
                            ? Offset(p.x.toDouble(), p.y.toDouble())
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    c.play.removeListener(refresh);
    c.play.pause();
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    focus.dispose();
    super.dispose();
  }
}

class _PlayPainter extends CustomPainter {
  _PlayPainter(this.payload, this.player);
  final Map<String, dynamic>? payload;
  final Offset? player;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xff20252b), BlendMode.src);
    final geometry = payload?['geometry'];
    if (geometry == null) {
      return;
    }
    final floor = geometry['layers']['floor'] as List;
    final tile = player == null
        ? math.min(
            size.width / (floor.first as String).length,
            size.height / floor.length,
          )
        : 22.0;
    final center =
        player ?? Offset((floor.first as String).length / 2, floor.length / 2);
    final origin =
        Offset(size.width / 2, size.height / 2) -
        (center + const Offset(.5, .5)) * tile;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    final minX = math.max(0, (-origin.dx / tile).floor()),
        maxX = math.min(
          (floor.first as String).length,
          ((size.width - origin.dx) / tile).ceil(),
        );
    final minY = math.max(0, (-origin.dy / tile).floor()),
        maxY = math.min(
          floor.length,
          ((size.height - origin.dy) / tile).ceil(),
        );
    final paint = Paint();
    for (var y = minY; y < maxY; y++) {
      for (var x = minX; x < maxX; x++) {
        if (floor[y][x] == '1') {
          paint.color = const Color(0xff808b82);
          canvas.drawRect(Rect.fromLTWH(x * tile, y * tile, tile, tile), paint);
        }
      }
    }
    void marker(dynamic point, Color color, double radius) {
      paint.color = color;
      canvas.drawCircle(
        Offset((point['x'] + .5) * tile, (point['y'] + .5) * tile),
        tile * radius,
        paint,
      );
    }

    for (final actor in payload?['allocation']?['actors'] as List? ?? []) {
      marker(actor['tile'], const Color(0xffe8b96b), .24);
    }
    marker(geometry['entrance_marker'], const Color(0xff58ca95), .42);
    marker(geometry['exit_marker'], const Color(0xffc7a8ff), .48);
    final exit = geometry['exit_marker'];
    final label = TextPainter(
      text: const TextSpan(
        text: 'EXIT',
        style: TextStyle(color: Colors.white, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(exit['x'] * tile, exit['y'] * tile - 14));
    if (player != null) {
      marker({'x': player!.dx, 'y': player!.dy}, Colors.white, .32);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlayPainter oldDelegate) => true;
}
