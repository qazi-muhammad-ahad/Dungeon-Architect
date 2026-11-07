import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'template_catalogue.dart';

import 'project_controller.dart';
import 'pixel_palette.dart';

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
    final packs = effectivePacks(
      c.play.snapshot?['source_project']?['source'] as Map?,
    );
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
    final markerCount =
        (s.payload?['allocation']?['actors'] as List? ?? []).length;
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
              ? c.stale
                    ? 'Inputs changed. Generate with encounters or place encounters again before exploring.'
                    : s.stale
                    ? 'Apply or restore the pending scenario before exploring.'
                    : 'Generate with encounters, then choose Start exploration.'
              : '${p.active ? p.message : 'Ready to explore. Choose Start exploration.'} · $markerCount encounter markers${markerCount == 0 ? ' placed by this allocation' : ' (dungeon sprites; press E within two tiles)'} · WASD/arrows move · Esc pauses',
        ),
        Expanded(
          child: Focus(
            focusNode: focus,
            onKeyEvent: key,
            onFocusChange: (value) {
              if (!value) {
                p.pause();
              }
              if (mounted) setState(() {});
            },
            child: Semantics(
              label: 'Exploration canvas',
              button: true,
              onTap: () => focus.requestFocus(),
              child: GestureDetector(
                onTap: () => focus.requestFocus(),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: focus.hasFocus
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipRect(
                    child: SizedBox.expand(
                      child: CustomPaint(
                        painter: _PlayPainter(
                          p.snapshot ?? s.payload,
                          p.active ? p.motion : null,
                          MediaQuery.devicePixelRatioOf(context),
                        ),
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
  _PlayPainter(this.payload, this.motion, this.dpr) : super(repaint: motion);
  final Map<String, dynamic>? payload;
  final ValueListenable<(double, double)>? motion;
  Offset? get player =>
      motion == null ? null : Offset(motion!.value.$1, motion!.value.$2);
  final double dpr;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(DungeonPixels.voidColor, BlendMode.src);
    final geometry = payload?['geometry'];
    if (geometry == null) {
      final label = TextPainter(
        text: const TextSpan(
          text: 'Generate with encounters, then Start exploration.',
          style: TextStyle(color: Colors.white, fontSize: 13),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: math.max(1, size.width - 32));
      label.paint(
        canvas,
        Offset(
          (size.width - label.width) / 2,
          (size.height - label.height) / 2,
        ),
      );
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
    canvas.translate(
      (origin.dx * dpr).round() / dpr,
      (origin.dy * dpr).round() / dpr,
    );
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
    final paint = Paint()..isAntiAlias = false;
    Rect tileRect(dynamic point) =>
        Rect.fromLTWH(point['x'] * tile, point['y'] * tile, tile, tile);
    final walls = geometry['layers']['walls'] as List?;
    for (var y = minY; y < maxY; y++) {
      for (var x = minX; x < maxX; x++) {
        final r = Rect.fromLTWH(x * tile, y * tile, tile, tile);
        if (floor[y][x] == '1') {
          paint.color = DungeonPixels.floor;
          canvas.drawRect(DungeonPixels.snap(r, dpr), paint);
          DungeonPixels.motif(canvas, r, 'floor', dpr, variant: x + y * 7);
        } else if (walls != null && walls[y][x] == '1') {
          paint.color = DungeonPixels.wall;
          canvas.drawRect(DungeonPixels.snap(r, dpr), paint);
          DungeonPixels.motif(canvas, r, 'wall', dpr, variant: x + y * 7);
        }
      }
    }
    for (final door in geometry['doors'] as List? ?? []) {
      for (final point in door['tiles'] as List) {
        DungeonPixels.motif(canvas, tileRect(point), 'door', dpr);
      }
    }
    final actors = payload?['allocation']?['actors'] as List? ?? [];
    String? playerOnMarker;
    for (final actor in actors) {
      final location = actor['tile'];
      if (player?.dx == location['x'] && player?.dy == location['y']) {
        playerOnMarker = DungeonPixels.encounterKind(
          actor as Map,
          payload?['source_project']?['source'] as Map?,
        );
      } else {
        DungeonPixels.motif(
          canvas,
          tileRect(location),
          DungeonPixels.encounterKind(
            actor as Map,
            payload?['source_project']?['source'] as Map?,
          ),
          dpr,
        );
      }
    }
    DungeonPixels.motif(
      canvas,
      tileRect(geometry['entrance_marker']),
      'entrance',
      dpr,
    );
    DungeonPixels.motif(canvas, tileRect(geometry['exit_marker']), 'exit', dpr);
    // Font size is independent of the world tile scale.
    final exit = geometry['exit_marker'];
    final label = TextPainter(
      text: const TextSpan(
        text: 'EXIT',
        style: TextStyle(
          color: Colors.white,
          backgroundColor: DungeonPixels.voidColor,
          fontSize: 11,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(exit['x'] * tile, exit['y'] * tile - 14));
    if (player != null) {
      final playerTile = Rect.fromLTWH(
        player!.dx * tile,
        player!.dy * tile,
        tile,
        tile,
      );
      DungeonPixels.motif(canvas, playerTile, 'player', dpr);
      if (playerOnMarker != null) {
        final corner = playerTile.topRight + const Offset(-4, 4);
        DungeonPixels.motif(
          canvas,
          Rect.fromCircle(center: corner, radius: 4),
          playerOnMarker,
          dpr,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlayPainter oldDelegate) =>
      oldDelegate.payload != payload ||
      oldDelegate.motion != motion ||
      oldDelegate.dpr != dpr;
}
