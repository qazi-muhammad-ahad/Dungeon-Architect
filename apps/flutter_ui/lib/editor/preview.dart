import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/engine.dart';
import 'camera.dart';
import 'canvas_history.dart';
import 'exact_json.dart';
import 'project_controller.dart';
import 'theme.dart';
import 'pixel_palette.dart';

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
  EngineResult? pending;
  Map<String, dynamic>? previewSource;
  int previewRevision = -1;
  List<dynamic> errors = [];
  Map<String, dynamic>? dragRoom;
  ProjectController get c => widget.controller;
  int get columns => c.settings['columns'] as int? ?? 150;
  int get rows => c.settings['rows'] as int? ?? 150;
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
        event.buttons == kMiddleMouseButton || space || tool == CanvasTool.pan;
    if (panning) return;
    if (event.buttons != kPrimaryMouseButton) return;
    final point = camera.tileAt(event.localPosition, columns, rows);
    if (point == null) return;
    if (c.view == EditorView.analyze &&
        c.scenario.blocking &&
        !c.stale &&
        !c.scenario.busy) {
      final g = c.payload?['geometry'];
      final entrance = g?['entrance_marker'];
      final floor = g?['layers']?['floor'] as List?;
      if (floor != null &&
          floor[point.y][point.x] == '1' &&
          (point.x != entrance['x'] || point.y != entrance['y'])) {
        c.scenario.toggleTile(point.x, point.y);
      }
      return;
    }
    if (!design || tool == CanvasTool.select) {
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
      if (c.view == EditorView.analyze) {
        int? node;
        for (final n in c.payload?['layout']?['partitions'] as List? ?? []) {
          final b = n['bounds'];
          if (point.x >= b['x'] &&
              point.y >= b['y'] &&
              point.x < b['x'] + b['width'] &&
              point.y < b['y'] + b['height']) {
            node = n['id'] as int;
          }
        }
        c.selectPartition(node);
      }
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
    return Column(
      children: [
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
                  cursor: tool == CanvasTool.pan || space
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
                      if (!waiting) cancelPreview();
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
                    onPointerPanZoomUpdate: (event) => setState(() {
                      camera.pan(event.panDelta);
                    }),
                    child: Semantics(
                      label: 'Design tile canvas. Wheel zooms; Space or middle drag pans. Use toolbar tools to edit.',
                      image: true,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: next,
                          painter: CanvasPainter(
                            camera: camera,
                            dpr: MediaQuery.devicePixelRatioOf(context),
                            source: previewSource ?? c.source,
                            payload: c.view == EditorView.analyze
                                ? c.scenario.displayPayload
                                : c.payload,
                            blockedTiles: c.view == EditorView.analyze
                                ? c.scenario.blocked
                                : const {},
                            analysis:
                                pending?.document['editor_analysis']
                                    as Map<String, dynamic>? ??
                                c.editorAnalysis,
                            colors: colors,
                            grid: widget.grid,
                            diagnostics: diagnostics,
                            reservations: reservations,
                            floor: showFloor,
                            walls: showWalls,
                            selected: c.selectedRoom,
                            overlays: c.view == EditorView.analyze
                                ? c.overlays
                                : null,
                            selectedPartition: c.view == EditorView.analyze
                                ? c.selectedPartition
                                : null,
                            traceEvent: c.view == EditorView.analyze
                                ? c.playback.current
                                : null,
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
              );
            },
          ),
        ),
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
    this.overlays,
    this.selectedPartition,
    this.traceEvent,
    this.stroke = const {},
    this.erase = false,
    this.dragStart,
    this.dragEnd,
    this.shape = false,
    this.errors = const [],
    this.blockedTiles = const {},
  });
  final CanvasCamera camera;
  final double dpr;
  final Map<String, dynamic> source, analysis;
  final Map<String, dynamic>? payload;
  final EditorColors colors;
  final bool grid, diagnostics, reservations, floor, walls, erase, shape;
  final String? selected;
  final Set<String>? overlays;
  final int? selectedPartition;
  final Map<String, dynamic>? traceEvent;
  bool show(String key) => overlays == null || overlays!.contains(key);
  final Set<int> stroke;
  final Point<int>? dragStart, dragEnd;
  final List<dynamic> errors;
  final Set<String> blockedTiles;
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

    if (show('mask')) {
      layer(
        source['allowed_mask'] as List?,
        colors.dark ? const Color(0xFF38393C) : const Color(0xFFF7F8F4),
      );
    }
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
    if (walls) {
      layer(geometry?['layers']?['walls'] as List?, DungeonPixels.wall);
    }
    if (floor) {
      layer(
        geometry?['layers']?['floor'] as List?,
        colors.dark ? DungeonPixels.floor : const Color(0xffd5dfd2),
      );
    }
    // Details are omitted below eight logical pixels per tile; boundaries remain crisp.
    if (s >= 8) {
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
            DungeonPixels.motif(canvas, rect(x, y, 1, 1), kind, dpr);
          }
        }
      }
    }
    if (show('doors')) {
      for (final door in geometry?['doors'] as List? ?? []) {
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
      if ((show('room IDs') || (overlays != null && show('capacities'))) &&
          r.width > 20 &&
          r.height > 14) {
        final label = TextPainter(
          text: TextSpan(
            text:
                (entrance
                    ? 'IN'
                    : exit
                    ? 'OUT'
                    : room['id'].toString().replaceFirst(
                        RegExp(r'^(generated-|room-)'),
                        '',
                      )) +
                (overlays != null && show('capacities')
                    ? ' C${(geometry?['rooms'] as List? ?? []).where((r) => r['id'] == room['id']).map((r) => r['capacity']).firstOrNull ?? '?'}'
                    : ''),
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
    for (final kind in ['entrance', 'exit']) {
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
    for (final tile in blockedTiles) {
      final xy = tile.split(',').map(int.parse).toList();
      canvas.drawRect(
        rect(xy[0], xy[1], 1, 1),
        Paint()..color = Colors.redAccent.withValues(alpha: .8),
      );
    }
    if (show('assignments')) {
      for (final actor in payload?['allocation']?['actors'] as List? ?? []) {
        final tile = actor['tile'],
            point = camera.toScreen(Offset(tile['x'] + .5, tile['y'] + .5));
        if ((Offset.zero & size).contains(point)) {
          DungeonPixels.motif(
            canvas,
            rect(tile['x'], tile['y'], 1, 1),
            'encounter',
            dpr,
          );
        }
      }
    }
    if (overlays != null) {
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

      for (final n in payload?['layout']?['partitions'] as List? ?? []) {
        if (show('partition bounds') || n['id'] == selectedPartition) {
          outline(
            n['bounds'],
            n['id'] == selectedPartition
                ? Colors.orange
                : colors.violet.withValues(alpha: .4),
            n['id'] == selectedPartition ? 3 : 1,
          );
        }
      }
      if (show('connectivity')) {
        for (final corridor in geometry?['corridors'] as List? ?? []) {
          final path = corridor['path'] as List;
          if (path.isEmpty) continue;
          final line = Path();
          for (var i = 0; i < path.length; i++) {
            final t = path[i];
            final p = camera.toScreen(Offset(t['x'] + .5, t['y'] + .5));
            if (i == 0) {
              line.moveTo(p.dx, p.dy);
            } else {
              line.lineTo(p.dx, p.dy);
            }
          }
          canvas.drawPath(
            line,
            Paint()
              ..color = colors.moss
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
      final event = traceEvent?['event'];
      if (event != null) {
        outline(event['bounds'], Colors.amber, 3);
        for (final room in payload?['layout']?['rooms'] as List? ?? []) {
          if (room['id'] == event['room_id']) {
            outline(room['bounds'], Colors.amber, 3);
          }
        }
        final tile = event['tile'];
        if (tile != null) {
          canvas.drawCircle(
            camera.toScreen(Offset(tile['x'] + .5, tile['y'] + .5)),
            math.max(3, s),
            Paint()..color = Colors.amber.withValues(alpha: .8),
          );
        }
        final corridorId = event['corridor_id'];
        if (corridorId != null) {
          for (final corridor in geometry?['corridors'] as List? ?? []) {
            if (corridor['id'] == corridorId) {
              for (final tile in corridor['path'] as List) {
                canvas.drawRect(
                  rect(tile['x'], tile['y'], 1, 1),
                  Paint()..color = Colors.amber.withValues(alpha: .6),
                );
              }
            }
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
    canvas.drawRect(
      rect(0, 0, w, h),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = colors.muted,
    );
    canvas.restore();
    paintMicros = timer.elapsedMicroseconds;
  }

  @override
  bool shouldRepaint(CanvasPainter old) => true;
}
