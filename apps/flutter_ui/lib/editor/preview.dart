import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'analysis_panel.dart';
import 'camera.dart';
import 'canvas_history.dart';
import 'exact_json.dart';
import 'project_controller.dart';
import 'theme.dart';
import 'pixel_palette.dart';
import 'routing_replay.dart';
import 'analysis_controller.dart';
import 'allocation_decision.dart';

enum CanvasTool {
  select,
  pan,
  paint,
  erase,
  fill,
  clear,
  rectangle,
  ellipse,
  lShape,
  room,
  moveRoom,
  resizeRoom,
}

class DungeonPreview extends StatefulWidget {
  const DungeonPreview({
    super.key,
    required this.controller,
    required this.grid,
  });
  final ProjectController controller;
  final bool grid;
  @override
  State<DungeonPreview> createState() => _DungeonPreviewState();
}

class _DungeonPreviewState extends State<DungeonPreview> {
  final camera = CanvasCamera(), history = CanvasHistory(), focus = FocusNode();
  final routingReplay = RoutingReplay();
  final Set<int> stroke = {};
  CanvasTool tool = CanvasTool.select;
  int brush = 1;
  String mode = 'add';
  bool diagnostics = false,
      reservations = true,
      showFloor = true,
      showWalls = true,
      space = false,
      panning = false,
      waiting = false;
  Point<int>? hover, start, last;
  Size viewport = Size.zero;
  double trackpadScale = 1;
  EngineResult? pending;
  Map<String, dynamic>? previewSource;
  int previewRevision = -1;
  List<dynamic> errors = [];
  Map<String, dynamic>? dragRoom;
  ProjectController get c => widget.controller;
  Map<String, dynamic> get canvasSource =>
      (!design
          ? c.payload?['source_project']?['source'] as Map<String, dynamic>?
          : null) ??
      previewSource ??
      c.source;
  int get columns => canvasSource['settings']?['columns'] as int? ?? 150;
  int get rows => canvasSource['settings']?['rows'] as int? ?? 150;
  bool get design => c.view == EditorView.design;
  bool get editable =>
      c.document != null &&
      !c.loading &&
      !c.validating &&
      c.fieldErrors.isEmpty &&
      !waiting &&
      pending == null;
  bool get shape =>
      tool.index >= CanvasTool.rectangle.index &&
      tool.index <= CanvasTool.lShape.index;
  bool get roomTool => tool.index >= CanvasTool.room.index;
  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  void cancelPreview() {
    pending = null;
    previewSource = null;
    stroke.clear();
    start = null;
    last = null;
    errors = [];
    dragRoom = null;
    c.setCanvasDraft(false);
    refresh();
  }

  void fit() {
    camera.fit(viewport, columns, rows);
    refresh();
  }

  void addPoint(Point<int> point) {
    for (final p in strokeLine(last ?? point, point)) {
      final offset = (brush - 1) ~/ 2;
      for (var y = p.y - offset; y < p.y - offset + brush; y++) {
        for (var x = p.x - offset; x < p.x - offset + brush; x++) {
          if (x >= 0 && y >= 0 && x < columns && y < rows) {
            stroke.add(y * columns + x);
          }
        }
      }
    }
    last = point;
  }

  Point<int> bounded(Offset pixel) {
    final p = camera.toWorld(pixel);
    return Point(
      p.dx.floor().clamp(0, columns - 1),
      p.dy.floor().clamp(0, rows - 1),
    );
  }

  void down(PointerDownEvent event) {
    focus.requestFocus();
    if (waiting || pending != null) return;
    panning =
        event.buttons == kMiddleMouseButton ||
        (event.buttons == kPrimaryMouseButton &&
            (!design || space || tool == CanvasTool.pan));
    if (!design || panning) return;
    if (event.buttons != kPrimaryMouseButton) return;
    final point = camera.tileAt(event.localPosition, columns, rows);
    if (point == null) return;
    if (tool == CanvasTool.select) {
      String? id;
      for (final room in c.editableRooms.reversed) {
        final b = room['bounds'];
        if (point.x >= b['x'] &&
            point.y >= b['y'] &&
            point.x < b['x'] + b['width'] &&
            point.y < b['y'] + b['height']) {
          id = room['id'];
          break;
        }
      }
      c.select(id);
      return;
    }
    if (!editable) return;
    dragRoom = null;
    if (tool == CanvasTool.moveRoom || tool == CanvasTool.resizeRoom) {
      final matches = c.editableRooms.where((r) {
        final b = r['bounds'];
        return point.x >= b['x'] &&
            point.y >= b['y'] &&
            point.x < b['x'] + b['width'] &&
            point.y < b['y'] + b['height'];
      });
      if (matches.isEmpty) {
        c.note('Click an unlocked source room to move or resize.');
        return;
      }
      final room = matches.last;
      if (c.roomFixed(room['id'] as String)) {
        c.select(room['id'] as String);
        c.note('Unlock room explicitly before moving or resizing it.');
        return;
      }
      if (!(c.source['rooms'] as List? ?? []).any(
        (r) => r['id'] == room['id'],
      )) {
        c.note(
          'Fix this generated room, then unlock it before changing geometry.',
        );
        return;
      }
      dragRoom = decodeExact(encodeExact(room)) as Map<String, dynamic>;
      c.select(room['id'] as String);
    }
    errors = [];
    start = point;
    last = point;
    c.setCanvasDraft(true);
    if (tool == CanvasTool.paint || tool == CanvasTool.erase) addPoint(point);
    if (tool == CanvasTool.fill || tool == CanvasTool.clear) {
      start = null;
      unawaited(
        command({
          'type': 'fill',
          'x': point.x,
          'y': point.y,
          'allowed': tool == CanvasTool.fill,
        }),
      );
    }
    refresh();
  }

  void move(PointerMoveEvent event) {
    hover = camera.tileAt(event.localPosition, columns, rows);
    if (panning) {
      camera.pan(event.delta);
      refresh();
      return;
    }
    if (start != null && !waiting) {
      final p = bounded(event.localPosition);
      if (tool == CanvasTool.paint || tool == CanvasTool.erase) {
        addPoint(p);
      } else {
        last = p;
      }
    }
    refresh();
  }

  void up(PointerUpEvent event) {
    if (panning) {
      panning = false;
      return;
    }
    if (start == null || waiting) return;
    if (roomTool) {
      final a = start!, b = last ?? a;
      final room =
          dragRoom ??
          <String, dynamic>{
            'id': c.nextRoomId(),
            'name': 'Fixed room',
            'role': 'normal',
            'tags': <String>[],
            'capacity_override': null,
          };
      if (tool == CanvasTool.room) {
        room['bounds'] = {
          'x': math.min(a.x, b.x),
          'y': math.min(a.y, b.y),
          'width': (a.x - b.x).abs() + 1,
          'height': (a.y - b.y).abs() + 1,
        };
      } else {
        final bounds = Map<String, dynamic>.from(room['bounds'] as Map);
        if (tool == CanvasTool.moveRoom) {
          bounds['x'] += b.x - a.x;
          bounds['y'] += b.y - a.y;
        } else {
          bounds['width'] = b.x - bounds['x'] + 1;
          bounds['height'] = b.y - bounds['y'] + 1;
        }
        room['bounds'] = bounds;
      }
      room['lock_position'] = true;
      room['lock_size'] = true;
      start = null;
      unawaited(command({'type': 'upsert_room', 'room': room}, preview: true));
    } else if (shape) {
      final a = start!, b = last ?? a;
      start = null;
      unawaited(
        command({
          'type': 'shape',
          'shape': tool == CanvasTool.lShape ? 'l_shape' : tool.name,
          'mode': mode,
          'x': math.min(a.x, b.x),
          'y': math.min(a.y, b.y),
          'width': (a.x - b.x).abs() + 1,
          'height': (a.y - b.y).abs() + 1,
        }, preview: true),
      );
    } else {
      start = null;
      unawaited(
        command({
          'type': 'paint',
          'allowed': tool == CanvasTool.paint,
          'tiles': stroke
              .map((i) => {'x': i % columns, 'y': i ~/ columns})
              .toList(),
        }),
      );
    }
  }

  Future<void> command(
    Map<String, dynamic> value, {
    bool preview = false,
  }) async {
    if (waiting) return;
    waiting = true;
    previewRevision = c.revision;
    c.setCanvasDraft(true);
    refresh();
    try {
      final response = await c.previewCanvas(value);
      if (!mounted) return;
      stroke.clear();
      if (!response.succeeded) {
        errors = response.document['diagnostics'] as List? ?? [];
        c.note(
          errors.isEmpty
              ? 'Edit rejected.'
              : '${errors.first['message']} ${errors.first['recovery'] ?? ''}',
        );
        c.setCanvasDraft(false);
      } else if (preview) {
        pending = response;
        previewSource =
            (decodeExact(response.document['project_json'] as String)
                    as Map)['source']
                as Map<String, dynamic>;
        c.note(
          roomTool
              ? 'Room preview. Apply to commit its position and size, or Cancel.'
              : 'Shape preview. Apply to commit, or Cancel to keep the current mask.',
        );
      } else {
        apply(response);
      }
    } catch (e) {
      if (mounted) {
        c.note('Canvas edit failed: $e');
        c.setCanvasDraft(false);
      }
    } finally {
      waiting = false;
      refresh();
    }
  }

  void apply(EngineResult response) {
    final old = CanvasSnapshot.of(c), before = c.canonical;
    if (c.commitCanvas(response, previewRevision) &&
        before != c.canonical &&
        !roomTool) {
      history.record(old);
    }
    if (roomTool) {
      final beforeIds = (decodeExact(before)['source']['rooms'] as List)
          .map((r) => r['id'])
          .toSet();
      final added = (c.source['rooms'] as List? ?? []).where(
        (r) => !beforeIds.contains(r['id']),
      );
      if (added.isNotEmpty) c.select(added.last['id'] as String);
      dragRoom = null;
    }
    pending = null;
    previewSource = null;
    c.setCanvasDraft(false);
    refresh();
  }

  Future<void> undo(bool redo) async {
    if (!editable || c.canvasDraft) return;
    final from = redo ? history.redo : history.undo,
        to = redo ? history.undo : history.redo;
    if (from.isEmpty) return;
    final target = from.last, old = CanvasSnapshot.of(c), stamp = c.revision;
    final draft = decodeExact(c.canonical) as Map<String, dynamic>;
    draft['source']['settings']['columns'] = target.columns;
    draft['source']['settings']['rows'] = target.rows;
    draft['source']['allowed_mask'] = target.mask;
    waiting = true;
    c.setCanvasDraft(true);
    refresh();
    try {
      final checked = await c.validateCanvasSource(encodeExact(draft));
      if (!mounted) return;
      if (c.commitCanvas(checked, stamp)) {
        from.removeLast();
        to.add(old);
        history.trim();
        errors = [];
      } else {
        c.note(
          'Cannot restore this canvas with the current project settings. History was kept.',
        );
      }
    } catch (e) {
      if (mounted) c.note('Undo failed: $e');
    } finally {
      waiting = false;
      if (mounted) c.setCanvasDraft(false);
      refresh();
    }
  }

  Future<void> resize() async {
    var w = columns, h = rows, crop = false;
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Resize canvas'),
          content: SizedBox(
            width: 330,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Top-left stays fixed. New tiles are disallowed. Rooms and their margins must fit; room locks are never removed.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: '$columns',
                  decoration: const InputDecoration(
                    labelText: 'Columns (1–512)',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setDialog(() => w = int.tryParse(v) ?? 0),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: '$rows',
                  decoration: const InputDecoration(labelText: 'Rows (1–512)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setDialog(() => h = int.tryParse(v) ?? 0),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: crop,
                  onChanged: (v) => setDialog(() => crop = v!),
                  title: const Text(
                    'Allow cropping tiles outside the new bounds',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: w >= 1 && w <= 512 && h >= 1 && h <= 512
                  ? () => Navigator.pop(context, {
                      'type': 'resize',
                      'columns': w,
                      'rows': h,
                      'allow_crop': crop,
                    })
                  : null,
              child: const Text('Resize'),
            ),
          ],
        ),
      ),
    );
    if (value != null && mounted && editable) await command(value);
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.space) {
      space = event is! KeyUpEvent;
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        !waiting &&
        (pending != null || start != null)) {
      cancelPreview();
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      unawaited(undo(HardwareKeyboard.instance.isShiftPressed));
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyY) {
      unawaited(undo(true));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      fit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget icon(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool selected = false,
  }) => IconButton(
    tooltip: label,
    isSelected: selected,
    style: selected
        ? IconButton.styleFrom(
            backgroundColor: EditorColors.of(context).lavender,
            foregroundColor: EditorColors.of(context).violet,
          )
        : null,
    onPressed: onPressed,
    icon: Icon(icon, size: 17),
  );
  @override
  Widget build(BuildContext context) {
    final colors = EditorColors.of(context);
    final routingActive =
        !design &&
        (c.playback.current?['stage'] == 'routing' ||
            (c.playback.selection == TraceSelection.routing &&
                c.playback.selectedEvents.isNotEmpty));
    routingReplay.update(
      c.playback.events,
      c.playback.currentOriginalIndex ?? -1,
    );
    final allocationDecision =
        !design &&
            c.playback.current?['stage'] == 'allocation' &&
            c.result != null
        ? AllocationDecision(c.playback.current!, c.result!.document)
        : null;
    final allocatedPacks = allocationDecision == null
        ? <String, String>{}
        : AllocationDecision.placements(
            c.playback.events,
            c.playback.currentOriginalIndex ?? -1,
            c.result!.document,
          );
    return Column(
      children: [
        if (!design)
          AnalyzePanel(
            controller: c,
            canvasActions: [
              icon('Fit canvas (F)', Icons.fit_screen, fit),
              icon(
                'Zoom in',
                Icons.add,
                () => setState(
                  () => camera.zoom(viewport.center(Offset.zero), 1.25),
                ),
              ),
              icon(
                'Zoom out',
                Icons.remove,
                () => setState(
                  () => camera.zoom(viewport.center(Offset.zero), .8),
                ),
              ),
            ],
          )
        else
          Material(
            color: colors.panel,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (design) ...[
                    PopupMenuButton<CanvasTool>(
                      tooltip: 'Room tools',
                      enabled: editable && !c.canvasDraft,
                      onSelected: (t) => setState(() => tool = t),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: CanvasTool.room,
                          child: Text('Draw fixed room'),
                        ),
                        const PopupMenuItem(
                          value: CanvasTool.moveRoom,
                          child: Text('Move unlocked room'),
                        ),
                        const PopupMenuItem(
                          value: CanvasTool.resizeRoom,
                          child: Text('Resize unlocked room'),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        child: Text(
                          'Room ▾',
                          style: TextStyle(
                            color: roomTool ? colors.violet : colors.ink,
                          ),
                        ),
                      ),
                    ),
                    for (final t in CanvasTool.values.take(4))
                      icon(
                        [
                          'Select room',
                          'Pan (Space / middle drag)',
                          'Paint allowed tiles',
                          'Erase allowed tiles',
                          'Fill connected area',
                          'Clear connected area',
                          'Rectangle preset',
                          'Ellipse preset',
                          'L-shape preset',
                        ][t.index],
                        [
                          Icons.near_me_outlined,
                          Icons.pan_tool_outlined,
                          Icons.brush_outlined,
                          Icons.auto_fix_normal,
                          Icons.format_color_fill,
                          Icons.format_color_reset,
                          Icons.crop_square,
                          Icons.circle_outlined,
                          Icons.turn_right,
                        ][t.index],
                        editable && !c.canvasDraft
                            ? () => setState(() => tool = t)
                            : null,
                        selected: tool == t,
                      ),
                    PopupMenuButton<CanvasTool>(
                      tooltip: 'Fill tools',
                      enabled: editable && !c.canvasDraft,
                      onSelected: (t) => setState(() => tool = t),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: CanvasTool.fill,
                          child: Text('Fill connected area'),
                        ),
                        PopupMenuItem(
                          value: CanvasTool.clear,
                          child: Text('Clear connected area'),
                        ),
                      ],
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        child: Text(
                          'Fill ▾',
                          style: TextStyle(
                            color:
                                tool == CanvasTool.fill ||
                                    tool == CanvasTool.clear
                                ? colors.violet
                                : colors.ink,
                          ),
                        ),
                      ),
                    ),
                    PopupMenuButton<CanvasTool>(
                      tooltip: 'Shape tools',
                      enabled: editable && !c.canvasDraft,
                      onSelected: (t) => setState(() => tool = t),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: CanvasTool.rectangle,
                          child: Text('Rectangle preset'),
                        ),
                        PopupMenuItem(
                          value: CanvasTool.ellipse,
                          child: Text('Ellipse preset'),
                        ),
                        PopupMenuItem(
                          value: CanvasTool.lShape,
                          child: Text('L-shape preset'),
                        ),
                      ],
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        child: Text(
                          'Shapes ▾',
                          style: TextStyle(
                            color: shape ? colors.violet : colors.ink,
                          ),
                        ),
                      ),
                    ),
                    icon(
                      'Undo mask stroke (Ctrl+Z)',
                      Icons.undo,
                      editable && !c.canvasDraft && history.undo.isNotEmpty
                          ? () => undo(false)
                          : null,
                    ),
                    icon(
                      'Redo mask stroke (Ctrl+Shift+Z)',
                      Icons.redo,
                      editable && !c.canvasDraft && history.redo.isNotEmpty
                          ? () => undo(true)
                          : null,
                    ),
                    icon(
                      'Resize canvas',
                      Icons.aspect_ratio,
                      editable && !c.canvasDraft ? resize : null,
                    ),
                  ],
                  icon('Fit canvas (F)', Icons.fit_screen, fit),
                  icon(
                    'Zoom in',
                    Icons.add,
                    () => setState(
                      () => camera.zoom(viewport.center(Offset.zero), 1.25),
                    ),
                  ),
                  icon(
                    'Zoom out',
                    Icons.remove,
                    () => setState(
                      () => camera.zoom(viewport.center(Offset.zero), .8),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Canvas layers',
                    icon: const Icon(Icons.layers_outlined, size: 17),
                    onSelected: (s) => setState(() {
                      if (s == 'floor') showFloor = !showFloor;
                      if (s == 'walls') showWalls = !showWalls;
                      if (s == 'reservations') reservations = !reservations;
                      if (s == 'diagnostics') diagnostics = !diagnostics;
                    }),
                    itemBuilder: (_) => [
                      CheckedPopupMenuItem(
                        value: 'floor',
                        checked: showFloor,
                        child: const Text('Generated floor'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'walls',
                        checked: showWalls,
                        child: const Text('Walls'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'reservations',
                        checked: reservations,
                        child: const Text('Fixed-room reservations'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'diagnostics',
                        checked: diagnostics,
                        child: const Text('Detached / narrow / rejected tiles'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (design)
          Container(
            height: 64,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.line)),
            ),
            child: Row(
              children: [
                if (tool == CanvasTool.paint || tool == CanvasTool.erase)
                  DropdownButton<int>(
                    value: brush,
                    items: [1, 2, 3, 5, 8, 16, 32]
                        .map(
                          (n) => DropdownMenuItem(
                            value: n,
                            child: Text('$n tile brush'),
                          ),
                        )
                        .toList(),
                    onChanged: editable && !c.canvasDraft
                        ? (n) => setState(() => brush = n!)
                        : null,
                  ),
                if (shape)
                  DropdownButton<String>(
                    value: mode,
                    items: ['add', 'subtract', 'replace']
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(
                              '${m[0].toUpperCase()}${m.substring(1)} shape',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: editable && !c.canvasDraft
                        ? (v) => setState(() => mode = v!)
                        : null,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    [
                      'Select · click a room, then use Fix room here in the inspector.',
                      'Pan · drag the canvas. Wheel to zoom; F to fit.',
                      'Paint · drag to add allowed tiles.',
                      'Erase · drag to remove allowed tiles.',
                      'Fill · click an area to allow connected tiles.',
                      'Clear · click an area to remove connected tiles.',
                      'Rectangle · drag, review the preview, then Apply.',
                      'Ellipse · drag, review the preview, then Apply.',
                      'L-shape · drag, review the preview, then Apply.',
                      'Fixed room · drag the interior, review, then Apply room.',
                      'Move · unlock the source room, then drag to preview its new origin.',
                      'Resize · unlock the source room, then drag toward its new bottom-right corner.',
                    ][tool.index],
                    style: TextStyle(fontSize: 11, color: colors.muted),
                  ),
                ),
              ],
            ),
          ),
        if (pending != null)
          Container(
            color: colors.lavender,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Expanded(child: Text('Preview · not applied')),
                TextButton(
                  onPressed: cancelPreview,
                  child: Text(roomTool ? 'Cancel room' : 'Cancel shape'),
                ),
                FilledButton(
                  onPressed: () => apply(pending!),
                  child: Text(roomTool ? 'Apply room' : 'Apply shape'),
                ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final next = Size(box.maxWidth, box.maxHeight);
              if (viewport == Size.zero) {
                camera.fit(next, columns, rows);
              } else if (next != viewport) {
                camera.pan(
                  Offset(
                    (next.width - viewport.width) / 2,
                    (next.height - viewport.height) / 2,
                  ),
                );
              }
              viewport = next;
              return Focus(
                focusNode: focus,
                onKeyEvent: key,
                onFocusChange: (v) {
                  if (!v) space = false;
                },
                child: MouseRegion(
                  cursor: !design || tool == CanvasTool.pan || space
                      ? SystemMouseCursors.grab
                      : tool == CanvasTool.select
                      ? SystemMouseCursors.basic
                      : SystemMouseCursors.precise,
                  onHover: (e) => setState(
                    () => hover = camera.tileAt(e.localPosition, columns, rows),
                  ),
                  onExit: (_) => setState(() => hover = null),
                  child: Listener(
                    onPointerDown: down,
                    onPointerMove: move,
                    onPointerUp: up,
                    onPointerCancel: (_) {
                      panning = false;
                      if (design && !waiting) cancelPreview();
                    },
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        GestureBinding.instance.pointerSignalResolver.register(
                          event,
                          (e) {
                            final scroll = e as PointerScrollEvent;
                            setState(() {
                              if (HardwareKeyboard.instance.isShiftPressed) {
                                camera.pan(-scroll.scrollDelta);
                              } else {
                                camera.zoom(
                                  scroll.localPosition,
                                  math.exp(-scroll.scrollDelta.dy * .0015),
                                );
                              }
                            });
                          },
                        );
                      }
                    },
                    onPointerPanZoomStart: (_) => trackpadScale = 1,
                    onPointerPanZoomUpdate: (event) => setState(() {
                      camera.pan(event.panDelta);
                      camera.zoom(
                        event.localPosition,
                        event.scale / trackpadScale,
                      );
                      trackpadScale = event.scale;
                    }),
                    child: Semantics(
                      label: design
                          ? 'Design tile canvas. Wheel zooms; Space or middle drag pans.'
                          : 'Trace canvas. Drag to pan; wheel zooms at the pointer.',
                      image: true,
                      child: RepaintBoundary(
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey((
                            c.playback.runId,
                            c.playback.currentOriginalIndex,
                            c.playback.playing,
                            c.playback.speed,
                            c.reduceTraceMotion,
                            MediaQuery.disableAnimationsOf(context),
                          )),
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration:
                              c.view != EditorView.analyze ||
                                  c.playback.current == null ||
                                  !c.playback.playing ||
                                  c.reduceTraceMotion ||
                                  MediaQuery.disableAnimationsOf(context) ||
                                  c.playback.speed > 10
                              ? Duration.zero
                              : Duration(
                                  milliseconds:
                                      ((allocationDecision == null
                                                  ? 650
                                                  : 800) /
                                              c.playback.speed)
                                          .clamp(
                                            30,
                                            allocationDecision == null
                                                ? 240
                                                : 700,
                                          )
                                          .round(),
                                ),
                          builder: (context, progress, _) => CustomPaint(
                            size: next,
                            painter: CanvasPainter(
                              camera: camera,
                              dpr: MediaQuery.devicePixelRatioOf(context),
                              source: canvasSource,
                              payload: c.payload,
                              analysis: design
                                  ? (pending?.document['editor_analysis']
                                            as Map<String, dynamic>? ??
                                        c.editorAnalysis)
                                  : const {},
                              colors: colors,
                              grid: widget.grid,
                              diagnostics: diagnostics,
                              reservations: reservations,
                              floor: showFloor,
                              walls: showWalls,
                              selected: design ? c.selectedRoom : null,
                              traceEvent: c.view == EditorView.analyze
                                  ? c.playback.current
                                  : null,
                              traceProgress: progress,
                              routingReplay: routingActive
                                  ? routingReplay
                                  : null,
                              allocationDecision: allocationDecision,
                              allocatedPacks: allocatedPacks,
                              tracePackOrder:
                                  c.result?.document['stages']?['allocation']?['pack_bit_order']
                                      as List? ??
                                  const [],
                              stroke: Set.of(stroke),
                              erase: tool == CanvasTool.erase,
                              dragStart: start,
                              dragEnd: last,
                              shape: shape || roomTool,
                              errors: errors,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (design)
          Container(
            color: colors.panel,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                Text(
                  hover == null ? 'Tile —' : 'Tile ${hover!.x}, ${hover!.y}',
                  style: TextStyle(fontSize: 11, color: colors.muted),
                ),
                const SizedBox(width: 12),
                Text(
                  '${camera.scale.toStringAsFixed(1)} px/tile',
                  style: TextStyle(fontSize: 11, color: colors.muted),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    waiting
                        ? 'Checking edit…'
                        : diagnostics
                        ? '/ detached · X no corridor-width clearance (zoom for pattern)'
                        : '$columns × $rows',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: colors.muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class CanvasPainter extends CustomPainter {
  CanvasPainter({
    required this.camera,
    required this.source,
    required this.payload,
    required this.analysis,
    required this.colors,
    required this.grid,
    required this.diagnostics,
    required this.reservations,
    required this.floor,
    required this.walls,
    this.dpr = 1,
    this.selected,
    this.traceEvent,
    this.traceProgress = 1,
    this.routingReplay,
    this.allocationDecision,
    this.allocatedPacks = const {},
    this.tracePackOrder = const [],
    this.stroke = const {},
    this.erase = false,
    this.dragStart,
    this.dragEnd,
    this.shape = false,
    this.errors = const [],
  });
  final CanvasCamera camera;
  final double dpr;
  final Map<String, dynamic> source, analysis;
  final Map<String, dynamic>? payload;
  final EditorColors colors;
  final bool grid, diagnostics, reservations, floor, walls, erase, shape;
  final String? selected;
  final Map<String, dynamic>? traceEvent;
  final double traceProgress;
  final RoutingReplay? routingReplay;
  final AllocationDecision? allocationDecision;
  final Map<String, String> allocatedPacks;
  final List<dynamic> tracePackOrder;
  final Set<int> stroke;
  final Point<int>? dragStart, dragEnd;
  final List<dynamic> errors;
  int visitedCells = 0, paintMicros = 0;
  @override
  void paint(Canvas canvas, Size size) {
    final timer = Stopwatch()..start();
    visitedCells = 0;
    final settings = source['settings'] as Map?;
    if (settings == null) return;
    final w = settings['columns'] as int,
        h = settings['rows'] as int,
        s = camera.scale;
    final visible = camera.visible(size, w, h);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawColor(colors.canvas, BlendMode.src);
    Rect rect(int x, int y, int width, int height) => DungeonPixels.snap(
      Rect.fromLTWH(
        camera.origin.dx + x * s,
        camera.origin.dy + y * s,
        width * s,
        height * s,
      ),
      dpr,
    );
    canvas.drawRect(
      rect(0, 0, w, h),
      Paint()
        ..color = colors.dark
            ? const Color(0xFF151517)
            : const Color(0xFFDCE0D8),
    );
    void layer(List<dynamic>? data, Color color) {
      if (data == null) return;
      final paint = Paint()
        ..color = color
        ..isAntiAlias = false;
      for (
        var y = visible.top.toInt();
        y < math.min(visible.bottom.toInt(), data.length);
        y++
      ) {
        final row = data[y] as String;
        for (
          var x = visible.left.toInt();
          x < math.min(visible.right.toInt(), row.length);
          x++
        ) {
          visitedCells++;
          if (row[x] != '1') continue;
          final begin = x;
          while (x + 1 < math.min(visible.right.toInt(), row.length) &&
              row[x + 1] == '1') {
            x++;
            visitedCells++;
          }
          canvas.drawRect(rect(begin, y, x - begin + 1, 1), paint);
        }
      }
    }

    layer(
      source['allowed_mask'] as List?,
      colors.dark ? const Color(0xFF38393C) : const Color(0xFFF7F8F4),
    );
    if (grid && s >= 2) {
      final paint = Paint()
        ..color = colors.line.withValues(alpha: .5)
        ..strokeWidth = .5;
      final step = s < 8 ? 10 : 1;
      for (
        var x = (visible.left ~/ step) * step;
        x <= visible.right;
        x += step
      ) {
        canvas.drawLine(
          camera.toScreen(Offset(x.toDouble(), visible.top)),
          camera.toScreen(Offset(x.toDouble(), visible.bottom)),
          paint,
        );
      }
      for (
        var y = (visible.top ~/ step) * step;
        y <= visible.bottom;
        y += step
      ) {
        canvas.drawLine(
          camera.toScreen(Offset(visible.left, y.toDouble())),
          camera.toScreen(Offset(visible.right, y.toDouble())),
          paint,
        );
      }
    }
    final geometry = payload?['geometry'];
    final finalGeometry =
        routingReplay == null || routingReplay!.geometryComplete;
    if (walls && finalGeometry) {
      layer(geometry?['layers']?['walls'] as List?, DungeonPixels.wall);
    }
    if (floor && finalGeometry) {
      layer(
        geometry?['layers']?['floor'] as List?,
        colors.dark ? DungeonPixels.floor : const Color(0xffd5dfd2),
      );
    }
    // Details are omitted below eight logical pixels per tile; boundaries remain crisp.
    if (s >= 8 && finalGeometry) {
      final layers = geometry?['layers'];
      bool occupied(String key, int x, int y) {
        final data = layers?[key] as List?;
        if (data == null || y >= data.length) return false;
        final row = data[y] as String;
        return x < row.length && row[x] == '1';
      }

      for (var y = visible.top.toInt(); y < visible.bottom.toInt(); y++) {
        for (var x = visible.left.toInt(); x < visible.right.toInt(); x++) {
          final kind = floor && occupied('floor', x, y)
              ? 'floor'
              : walls && occupied('walls', x, y)
              ? 'wall'
              : null;
          if (kind != null) {
            DungeonPixels.motif(
              canvas,
              rect(x, y, 1, 1),
              kind,
              dpr,
              variant: x + y * 7,
            );
          }
        }
      }
    }
    {
      for (final door in geometry?['doors'] as List? ?? []) {
        final route = routingReplay;
        if (route != null && !route.geometryComplete) continue;
        for (final tile in door['tiles'] as List) {
          DungeonPixels.motif(
            canvas,
            rect(tile['x'], tile['y'], 1, 1),
            'door',
            dpr,
          );
        }
      }
    }
    if (routingReplay != null && !routingReplay!.geometryComplete) {
      _paintRouting(canvas, size, rect, geometry);
    }
    if (reservations) {
      layer(
        analysis['reservations'] as List?,
        colors.moss.withValues(alpha: .35),
      );
    }
    if (diagnostics) {
      layer(analysis['detached'] as List?, Colors.amber.withValues(alpha: .32));
      layer(
        analysis['narrow'] as List?,
        Colors.redAccent.withValues(alpha: .4),
      );
      if (s >= 8) {
        void hatch(String key, bool cross) {
          final data = analysis[key] as List?;
          if (data == null) return;
          final paint = Paint()
            ..color = colors.ink
            ..strokeWidth = 1;
          for (
            var y = visible.top.toInt();
            y < math.min(visible.bottom.toInt(), data.length);
            y++
          ) {
            final row = data[y] as String;
            for (
              var x = visible.left.toInt();
              x < math.min(visible.right.toInt(), row.length);
              x++
            ) {
              if (row[x] != '1') continue;
              final r = rect(x, y, 1, 1).deflate(2);
              canvas.drawLine(r.bottomLeft, r.topRight, paint);
              if (cross) canvas.drawLine(r.topLeft, r.bottomRight, paint);
            }
          }
        }

        hatch('detached', false);
        hatch('narrow', true);
      }
    }
    for (final room in payload?['layout']?['rooms'] as List? ?? []) {
      final b = room['bounds'],
          r = rect(b['x'], b['y'], b['width'], b['height']);
      if (!r.overlaps(Offset.zero & size)) continue;
      final entrance = room['id'] == geometry?['entrance_room'],
          exit = room['id'] == geometry?['exit_room'];
      final disconnected = (geometry?['rooms'] as List? ?? []).any(
        (r) => r['id'] == room['id'] && r['reachable'] == false,
      );
      final color = disconnected
          ? Colors.redAccent
          : entrance
          ? colors.moss
          : colors.violet;
      canvas.drawRect(r, Paint()..color = color.withValues(alpha: .12));
      canvas.drawRect(
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = room['id'] == selected ? 2 : 1,
      );
      if (r.width > 20 && r.height > 14) {
        final label = TextPainter(
          text: TextSpan(
            text: (entrance
                ? 'IN'
                : exit
                ? 'OUT'
                : room['id'].toString().replaceFirst(
                    RegExp(r'^(generated-|room-)'),
                    '',
                  )),
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
              backgroundColor: colors.paper.withValues(alpha: .94),
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: r.width - 4);
        label.paint(
          canvas,
          r.center - Offset(label.width / 2, label.height / 2),
        );
      }
    }
    for (final kind in finalGeometry ? ['entrance', 'exit'] : <String>[]) {
      final point = geometry?['${kind}_marker'];
      if (point != null) {
        DungeonPixels.motif(
          canvas,
          rect(point['x'], point['y'], 1, 1),
          kind,
          dpr,
        );
      }
    }
    if (selected != null) {
      for (final room in payload?['layout']?['rooms'] as List? ?? []) {
        if (room['id'] != selected) continue;
        final b = room['bounds'],
            r = rect(b['x'], b['y'], b['width'], b['height']);
        canvas.drawRect(
          r.inflate(2),
          Paint()
            ..color = colors.paper
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
        canvas.drawRect(
          r.inflate(2),
          Paint()
            ..color = colors.violet
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    for (final room in source['rooms'] as List? ?? []) {
      final b = room['bounds'];
      canvas.drawRect(
        rect(b['x'], b['y'], b['width'], b['height']),
        Paint()
          ..color = colors.moss
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (traceEvent == null && routingReplay == null) {
      for (final actor in payload?['allocation']?['actors'] as List? ?? []) {
        final tile = actor['tile'],
            point = camera.toScreen(Offset(tile['x'] + .5, tile['y'] + .5));
        if ((Offset.zero & size).contains(point)) {
          DungeonPixels.motif(
            canvas,
            rect(tile['x'], tile['y'], 1, 1),
            DungeonPixels.encounterKind(
              actor as Map,
              payload?['source_project']?['source'] as Map? ?? source,
            ),
            dpr,
          );
        }
      }
    }
    if (traceEvent != null && routingReplay == null) {
      void outline(dynamic b, Color color, double stroke) {
        if (b == null || b['width'] == 0 || b['height'] == 0) return;
        canvas.drawRect(
          rect(b['x'], b['y'], b['width'], b['height']),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke,
        );
      }

      final event = traceEvent?['event'];
      if (event != null) {
        final kind = event['kind'].toString();
        final rejected =
            kind.contains('rejected') ||
            kind.contains('infeasible') ||
            kind == 'backtrack';
        final color = rejected ? Colors.redAccent : Colors.amber;
        final highlight = Paint()..color = color;
        final bounds = event['bounds'];
        if (bounds != null) {
          outline(bounds, color, rejected ? 2 : 3);
          final box = rect(
            bounds['x'],
            bounds['y'],
            bounds['width'],
            bounds['height'],
          );
          if (kind == 'room_placed' || kind == 'fixed_reserved') {
            canvas.drawRect(
              Rect.fromLTWH(
                box.left,
                box.top,
                box.width * traceProgress,
                box.height,
              ),
              Paint()..color = color.withValues(alpha: .28),
            );
          }
          if (kind == 'split_selected') {
            final vertical = event['reason'] == 'x';
            final cut = event['cut'] as int;
            final start = vertical
                ? camera.toScreen(
                    Offset(cut.toDouble(), (bounds['y'] as int).toDouble()),
                  )
                : camera.toScreen(
                    Offset((bounds['x'] as int).toDouble(), cut.toDouble()),
                  );
            final end =
                start +
                (vertical ? Offset(0, box.height) : Offset(box.width, 0));
            canvas.drawLine(
              start,
              Offset.lerp(start, end, traceProgress)!,
              Paint()
                ..color = color
                ..strokeWidth = 3,
            );
          }
        }
        final corridorId = event['corridor_id'];
        final links = geometry?['corridors'] as List? ?? [];
        final link = corridorId == null || corridorId == ''
            ? null
            : links.where((link) => link['id'] == corridorId).firstOrNull;
        for (final room in payload?['layout']?['rooms'] as List? ?? []) {
          if (room['id'] == event['room_id'] ||
              room['id'] == link?['from_room'] ||
              room['id'] == link?['to_room']) {
            outline(room['bounds'], color, 3);
          }
        }
        final tile = event['tile'];
        if (tile != null) {
          final point = camera.toScreen(Offset(tile['x'] + .5, tile['y'] + .5));
          canvas.drawCircle(
            point,
            math.max(3, s * (.55 + .45 * traceProgress)),
            highlight,
          );
        }
        if (kind == 'corridor_routed' && link != null) {
          final path = link['path'] as List;
          final visible = (path.length * traceProgress).ceil();
          for (final tile in path.take(visible)) {
            canvas.drawRect(
              rect(tile['x'], tile['y'], 1, 1),
              Paint()..color = color.withValues(alpha: .75),
            );
          }
        }
        if (allocationDecision == null &&
            (kind == 'reconstruct' || kind == 'optimal')) {
          final subset = event['subset'] as int? ?? 0;
          final packs = {
            for (var i = 0; i < tracePackOrder.length; i++)
              if ((subset & (1 << i)) != 0) tracePackOrder[i],
          };
          final actors = payload?['allocation']?['actors'] as List? ?? [];
          final matching = kind == 'optimal'
              ? actors
              : actors
                    .where(
                      (a) =>
                          a['room_id'] == event['room_id'] &&
                          packs.contains(a['pack_id']),
                    )
                    .toList();
          for (final actor in matching.take(
            (matching.length * traceProgress).ceil(),
          )) {
            final tile = actor['tile'];
            DungeonPixels.motif(
              canvas,
              rect(tile['x'], tile['y'], 1, 1),
              DungeonPixels.encounterKind(
                actor as Map,
                payload?['source_project']?['source'] as Map? ?? source,
              ),
              dpr,
            );
          }
        }
      }
    }
    for (final index in stroke) {
      final r = rect(index % w, index ~/ w, 1, 1);
      if (r.overlaps(Offset.zero & size)) {
        canvas.drawRect(
          r,
          Paint()
            ..color = (erase ? Colors.redAccent : colors.moss).withValues(
              alpha: .7,
            ),
        );
      }
    }
    if (shape && dragStart != null && dragEnd != null) {
      final a = dragStart!, b = dragEnd!;
      canvas.drawRect(
        rect(
          math.min(a.x, b.x),
          math.min(a.y, b.y),
          (a.x - b.x).abs() + 1,
          (a.y - b.y).abs() + 1,
        ),
        Paint()
          ..color = colors.violet
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (diagnostics) {
      for (final error in errors) {
        for (final tile in error['affected_tiles'] as List? ?? []) {
          canvas.drawRect(
            rect(tile['x'], tile['y'], 1, 1).inflate(2),
            Paint()
              ..color = Colors.red
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
        }
      }
    }
    if (allocationDecision != null) _paintAllocation(canvas, size);
    if (routingReplay != null) _paintRoutingLegend(canvas, size);
    canvas.drawRect(
      rect(0, 0, w, h),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = colors.muted,
    );
    canvas.restore();
    paintMicros = timer.elapsedMicroseconds;
  }

  void _paintRouting(
    Canvas canvas,
    Size size,
    Rect Function(int, int, int, int) rect,
    dynamic geometry,
  ) {
    final replay = routingReplay!;
    final visible = Offset.zero & size;
    final scale = camera.scale;
    final searching =
        replay.phase == 'routing_started' || replay.phase == 'search_batch';
    final carving = const {
      'carve_batch',
      'carving_finished',
      'corridor_routed',
      'room_reachable',
    }.contains(replay.phase);
    final searchOpacity = searching
        ? 1.0
        : carving
        ? .08
        : .2;
    void floorTile(int x, int y) {
      final tile = rect(x, y, 1, 1);
      if (!tile.overlaps(visible)) return;
      canvas.drawRect(tile, Paint()..color = DungeonPixels.floor);
      DungeonPixels.motif(canvas, tile, 'floor', dpr, variant: x + y * 7);
    }

    // Room interiors are known before routing; future corridors are not shown.
    for (final room in payload?['layout']?['rooms'] as List? ?? []) {
      final b = room['bounds'];
      final box = rect(b['x'], b['y'], b['width'], b['height']);
      if (!box.overlaps(visible)) continue;
      canvas.drawRect(box, Paint()..color = DungeonPixels.floor);
      if (scale >= 8) {
        final view = camera.visible(
          size,
          source['settings']['columns'],
          source['settings']['rows'],
        );
        for (
          var y = math.max(b['y'] as int, view.top.toInt());
          y < math.min(b['y'] + b['height'], view.bottom.toInt());
          y++
        ) {
          for (
            var x = math.max(b['x'] as int, view.left.toInt());
            x < math.min(b['x'] + b['width'], view.right.toInt());
            x++
          ) {
            floorTile(x, y);
          }
        }
      }
      if (room['id'] == replay.fromRoom || room['id'] == replay.toRoom) {
        canvas.drawRect(
          box.inflate(1),
          Paint()
            ..color = const Color(0xff80dcb3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    final width = source['settings']['corridor_width'] as int;
    for (final corridor in geometry?['corridors'] as List? ?? []) {
      if (!replay.completedCorridors.contains(corridor['id'])) continue;
      for (final anchor in corridor['path'] as List) {
        for (var y = anchor['y'] as int; y < anchor['y'] + width; y++) {
          for (var x = anchor['x'] as int; x < anchor['x'] + width; x++) {
            floorTile(x, y);
          }
        }
      }
    }
    final currentSteps = traceEvent?['event']?['steps'] as List? ?? const [];
    final visibleSteps = (currentSteps.length * traceProgress).ceil();
    final pendingCarve = {
      if (traceEvent?['event']?['kind'] == 'carve_batch')
        for (final raw in currentSteps.skip(visibleSteps))
          '${replay.corridorId}:${raw['tile']['x']},${raw['tile']['y']}',
    };
    Offset center(TraceTile tile) =>
        camera.toScreen(Offset(tile.x + .5, tile.y + .5));
    for (final tile in replay.expanded.values) {
      final box = rect(tile.x, tile.y, replay.width, replay.width);
      if (box.overlaps(visible)) {
        canvas.drawRect(
          box,
          Paint()
            ..color = const Color(0xff4680a5)
                .withValues(alpha: .25 * searchOpacity),
        );
      }
    }
    for (final tile in replay.discovered.values) {
      final parent = replay.parents[tile.key];
      if (parent == null) continue;
      final edge = Rect.fromPoints(center(tile), center(parent)).inflate(2);
      if (!edge.overlaps(visible)) continue;
      canvas.drawLine(
        center(tile),
        center(parent),
        Paint()
          ..color = const Color(0xff78abd0)
              .withValues(alpha: .45 * searchOpacity)
          ..strokeWidth = math.max(1, scale * .1),
      );
    }
    for (final tile in replay.frontier) {
      final box = rect(tile.x, tile.y, replay.width, replay.width);
      if (!box.overlaps(visible)) continue;
      canvas.drawRect(
        box.deflate(scale > 4 ? .5 : 0),
        Paint()
          ..color = const Color(0xff80dcb3).withValues(alpha: searchOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, scale * .12),
      );
    }
    final reverseVisible = traceEvent?['event']?['kind'] == 'reconstruct_batch'
        ? replay.reconstructed.length - currentSteps.length + visibleSteps
        : replay.reconstructed.length;
    for (final tile in replay.reconstructed.take(reverseVisible)) {
      final parent = replay.parents[tile.key];
      if (parent != null) {
        canvas.drawLine(
          center(tile),
          center(parent),
          Paint()
            ..color = const Color(0xffffce79)
                .withValues(alpha: carving ? .25 : 1)
            ..strokeWidth = carving
                ? math.max(1, scale * .06)
                : math.max(2, scale * .3),
        );
      }
      if (!carving) {
        canvas.drawRect(
          rect(tile.x, tile.y, 1, 1).deflate(scale * .2),
          Paint()..color = const Color(0xffffce79),
        );
      }
    }
    // Stone is drawn above retained search/path evidence as the native carve progresses.
    for (final entry in replay.carved.entries) {
      if (pendingCarve.contains(entry.key)) continue;
      final (anchor, footprint) = entry.value;
      for (var y = anchor.y; y < anchor.y + footprint; y++) {
        for (var x = anchor.x; x < anchor.x + footprint; x++) {
          floorTile(x, y);
        }
      }
    }
    if (replay.phase == 'carve_batch') {
      for (final raw in currentSteps.take(visibleSteps)) {
        final tile = raw['tile'] as Map;
        canvas.drawRect(
          rect(tile['x'], tile['y'], replay.width, replay.width).deflate(.5),
          Paint()
            ..color = const Color(0xff80dcb3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.25,
        );
      }
    }
    for (final door in geometry?['doors'] as List? ?? []) {
      final selected = replay.selectedDoors.any(
        (id) =>
            id.endsWith(':${door['room_id']}') &&
            (door['id'] as String).startsWith(id.split(':').first),
      );
      if (!selected) continue;
      for (final point in door['tiles'] as List) {
        DungeonPixels.motif(
          canvas,
          rect(point['x'], point['y'], 1, 1),
          'door',
          dpr,
        );
      }
    }
    final current = replay.currentTile;
    if (current != null) {
      canvas.drawRect(
        rect(current.x, current.y, replay.width, replay.width).inflate(1),
        Paint()
          ..color = Colors.white.withValues(alpha: .65 + .35 * traceProgress)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _paintAllocation(Canvas canvas, Size size) {
    final decision = allocationDecision!;
    final kind = decision.kind;
    final reconstructing = kind == 'reconstruct';
    final summary = kind == 'room_summary' || kind == 'preflight';
    final room = decision.room;
    final bounds = room?['bounds'];
    final roomCenter = bounds == null
        ? null
        : camera.toScreen(
            Offset(
              bounds['x'] + bounds['width'] / 2,
              bounds['y'] + bounds['height'] / 2,
            ),
          );
    final targetWidth = size.width < 1000
        ? math.max(240.0, size.width * .4)
        : 470.0;
    final cardWidth = math.min(targetWidth, math.max(180.0, size.width - 24));
    final packs = decision.packs;
    final cardHeight = packs.isEmpty ? 164.0 : 244.0;
    final card = Rect.fromLTWH(
      roomCenter != null && roomCenter.dx < size.width / 2
          ? size.width - cardWidth - 12
          : 12,
      roomCenter != null && roomCenter.dy < size.height / 2
          ? math.max(12.0, size.height - cardHeight - 12)
          : 12,
      cardWidth,
      math.min(cardHeight, size.height - 24),
    );
    const ink = Color(0xffe3e7df),
        muted = Color(0xffb6c2c5),
        mint = Color(0xff80dcb3);
    const red = Color(0xfff19186), gold = Color(0xffffce79);
    void label(
      String value,
      Offset offset, {
      double width = 440,
      double fontSize = 11,
      Color color = ink,
      int lines = 2,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(fontSize: fontSize, height: 1.25, color: color),
        ),
        textDirection: TextDirection.ltr,
        maxLines: lines,
        ellipsis: '…',
      )..layout(maxWidth: math.max(1, width));
      painter.paint(canvas, offset);
    }

    Offset actorPoint(Map actor) => camera.toScreen(
      Offset(actor['tile']['x'] + .5, actor['tile']['y'] + .5),
    );
    final actors = payload?['allocation']?['actors'] as List? ?? [];
    final currentIds = packs.map((p) => p['id']).toSet();
    final spriteSize = camera.scale.clamp(10, 32).toDouble();
    for (final actor in actors) {
      final assigned = allocatedPacks[actor['pack_id']] == actor['room_id'];
      if (!assigned && kind != 'optimal') continue;
      if (reconstructing && currentIds.contains(actor['pack_id'])) continue;
      DungeonPixels.motif(
        canvas,
        Rect.fromCenter(
          center: actorPoint(actor),
          width: spriteSize,
          height: spriteSize,
        ),
        DungeonPixels.encounterKind(actor as Map, decision.source),
        dpr,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, const Radius.circular(8)),
      Paint()..color = const Color(0xf2171921),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, const Radius.circular(8)),
      Paint()
        ..color = const Color(0xff556477)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final title = reconstructing
        ? 'RECONSTRUCT · assign selected packs'
        : kind == 'optimal'
        ? 'EXACT WINNING INVENTORY'
        : summary
        ? 'ROOM SUMMARY · recorded state count'
        : kind.startsWith('state_')
        ? 'CHOOSE PREDECESSOR · recorded DP state'
        : 'CANDIDATE TRIAL · ${decision.sampled ? 'representative recorded transition' : 'recorded transition'}';
    label(
      title,
      card.topLeft + const Offset(12, 9),
      width: cardWidth - 24,
      fontSize: 12,
      color: gold,
      lines: 1,
    );
    final roomText = room == null
        ? 'Accepted inventory · global threat budget ${decision.budget ?? 'unavailable'}'
        : '${room['name'] ?? decision.roomId} · ${room['role']} · capacity ${decision.capacity ?? 'unavailable'} · ${room['bounds']['width']} × ${room['bounds']['height']} tiles · tags ${(room['tags'] as List? ?? []).join(', ')}';
    label(
      roomText,
      card.topLeft + const Offset(12, 29),
      width: cardWidth - 24,
      color: muted,
    );
    final shown = packs.take(math.max(1, (cardWidth - 24) ~/ 95)).toList();
    final chipWidth = (cardWidth - 24) / math.max(1, shown.length);
    final origins = <String, Offset>{};
    for (var i = 0; i < shown.length; i++) {
      final pack = shown[i];
      final origin = card.topLeft + Offset(12 + chipWidth * (i + .5), 79);
      origins[pack['id'] as String] = origin;
      DungeonPixels.motif(
        canvas,
        Rect.fromCenter(center: origin, width: 30, height: 30),
        DungeonPixels.encounterKind({'pack_id': pack['id']}, decision.source),
        dpr,
      );
      label(
        pack['name'] as String,
        card.topLeft + Offset(12 + chipWidth * i, 98),
        width: chipWidth - 4,
        lines: 1,
      );
      label(
        '${pack['slots']} slots · ${pack['threat']} threat',
        card.topLeft + Offset(12 + chipWidth * i, 113),
        width: chipWidth - 4,
        fontSize: 10,
        color: gold,
      );
      final roles = (pack['allowed_roles'] as List? ?? []).join('/');
      final tags = (pack['required_tags'] as List? ?? []).join('/');
      label(
        'min ${pack['min_room_width']}×${pack['min_room_height']} · ${roles.isEmpty ? 'any role' : roles}${tags.isEmpty ? '' : ' · $tags'}',
        card.topLeft + Offset(12 + chipWidth * i, 127),
        width: chipWidth - 4,
        fontSize: 9,
        color: muted,
      );
    }
    var y = packs.isEmpty ? 62.0 : 160.0;
    if (decision.evidence) {
      label(
        'Slots ${decision.slots} / ${decision.capacity}  ${decision.slotsFit == true ? 'PASS' : 'FAIL'}',
        card.topLeft + Offset(12, y),
        width: (cardWidth - 24) * .55,
        color: decision.slotsFit == true ? mint : red,
        lines: 1,
      );
      label(
        'Rules ${decision.compatible == true ? 'PASS' : 'FAIL'}',
        card.topLeft + Offset(cardWidth * .6, y),
        width: cardWidth * .4 - 12,
        color: decision.compatible == true ? mint : red,
        lines: 1,
      );
      label(
        'Prior F[room−1, ${decision.predecessor}] ${decision.priorFeasible == true ? 'PASS · reachable' : 'FAIL · unreachable'}',
        card.topLeft + Offset(12, y + 18),
        width: cardWidth - 24,
        color: decision.priorFeasible == true ? mint : red,
      );
      label(
        'Inventory threat ${decision.inventoryThreat} / budget ${decision.budget} · subset ${decision.subsetThreat}',
        card.topLeft + Offset(12, y + 36),
        width: cardWidth - 24,
        fontSize: 10,
      );
      label(
        reconstructing ? 'Recorded predecessor fixes this assignment.' : 'Budget is checked on the final inventory. Feasible trials remain candidates.',
        card.topLeft + Offset(12, y + 54),
        width: cardWidth - 24,
        fontSize: 10,
        color: muted,
      );
    } else {
      label(
        kind == 'room_summary'
            ? '${decision.event['states']} inventory states reachable after this room.'
            : kind == 'optimal'
            ? 'Final threat ${payload?['allocation']?['total_threat']} / budget ${decision.budget}'
            : 'Candidate feasibility evidence is unavailable at this step.',
        card.topLeft + Offset(12, y),
        width: cardWidth - 24,
      );
      label(
        summary
            ? 'Larger runs record representative candidates and room summaries.'
            : 'Only recorded transitions are animated.',
        card.topLeft + Offset(12, y + 24),
        width: cardWidth - 24,
        color: muted,
      );
    }
    if (packs.length > shown.length) {
      label(
        '+${packs.length - shown.length} other packs in this subset',
        card.bottomLeft + const Offset(12, -15),
        width: cardWidth - 24,
        fontSize: 9,
      );
    }

    if (roomCenter == null) return;
    for (final pack in packs) {
      final origin =
          origins[pack['id']] ?? card.bottomCenter - const Offset(0, 12);
      if (reconstructing) {
        for (final actor in actors.where(
          (a) => a['pack_id'] == pack['id'] && a['room_id'] == decision.roomId,
        )) {
          final target = actorPoint(actor as Map);
          final point = Offset.lerp(origin, target, traceProgress)!;
          DungeonPixels.motif(
            canvas,
            Rect.fromCenter(
              center: point,
              width: spriteSize,
              height: spriteSize,
            ),
            DungeonPixels.encounterKind(actor, decision.source),
            dpr,
          );
        }
      } else if (!summary && kind != 'optimal' && decision.evidence) {
        final target = Offset.lerp(
          origin,
          roomCenter,
          decision.feasible ? .75 : .35,
        )!;
        final point = Offset.lerp(origin, target, traceProgress)!;
        canvas.saveLayer(
          Rect.fromCenter(center: point, width: 42, height: 42),
          Paint()..color = Colors.white.withValues(alpha: .65),
        );
        DungeonPixels.motif(
          canvas,
          Rect.fromCenter(center: point, width: 24, height: 24),
          DungeonPixels.encounterKind({'pack_id': pack['id']}, decision.source),
          dpr,
        );
        canvas.restore();
        if (!decision.feasible) {
          label(
            '×',
            point + const Offset(8, -16),
            width: 20,
            fontSize: 20,
            color: red,
          );
        }
      }
    }
  }

  void _paintRoutingLegend(Canvas canvas, Size size) {
    final replay = routingReplay!;
    final label = TextPainter(
      text: TextSpan(
        text:
            '${replay.geometryComplete ? 'Validated geometry complete · derived walls and terminal markers shown' : 'QUEUE frontier ${replay.frontier.length}  ·  EXPANDED ${replay.expanded.length}  ·  PARENT links in blue'}\n'
            '${const {'carve_batch', 'carving_finished', 'corridor_routed'}.contains(replay.phase) ? 'CARVING stone floor · faded search and path retained for context' : 'PATH reconstruction in gold  ·  CARVED stone floor'}'
            '${replay.sampled ? '\nSampled capture · missing search/path steps omitted. Completed corridors use accepted final context.' : '\nOnly recorded search, parent, reconstruction and carve steps are displayed.'}',
        style: const TextStyle(
          fontSize: 11,
          height: 1.5,
          color: Color(0xffe3e7df),
          backgroundColor: Color(0xeb171921),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: math.max(1, size.width - 24));
    label.paint(canvas, const Offset(12, 12));
  }

  @override
  bool shouldRepaint(CanvasPainter old) => true;
}
