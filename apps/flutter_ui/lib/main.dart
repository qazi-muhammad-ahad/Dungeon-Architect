import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'editor/project_controller.dart';
import 'editor/files.dart';
import 'editor/preview.dart';
import 'editor/preferences.dart';
import 'editor/theme.dart';
import 'editor/widgets.dart';
import 'editor/record_editors.dart';

void main() => runApp(const DungeonArchitectApp());

class DungeonArchitectApp extends StatefulWidget {
  const DungeonArchitectApp({super.key, this.controller});
  final ProjectController? controller;
  @override
  State<DungeonArchitectApp> createState() => _DungeonArchitectAppState();
}

class _DungeonArchitectAppState extends State<DungeonArchitectApp> {
  bool dark = readDarkPreference();
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Dungeon Architect',
    debugShowCheckedModeBanner: false,
    theme: editorTheme(),
    darkTheme: editorTheme(dark: true),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: EditorShell(
      controller: widget.controller,
      onThemeToggle: () {
        setState(() => dark = !dark);
        writeDarkPreference(dark);
      },
    ),
  );
}

class EditorShell extends StatefulWidget {
  const EditorShell({super.key, this.controller, this.onThemeToggle});
  final VoidCallback? onThemeToggle;
  final ProjectController? controller;
  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  EditorColors get colors => EditorColors.of(context);
  Color get ink => colors.ink;
  Color get muted => colors.muted;
  Color get paper => colors.paper;
  Color get panel => colors.panel;
  Color get line => colors.line;
  Color get violet => colors.violet;
  Color get moss => colors.moss;
  Color get lavender => colors.lavender;
  late final ProjectController c = widget.controller ?? ProjectController();
  final ProjectFiles files = ProjectFiles();
  bool fileBusy = false, grid = true, inspector = true, console = true;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    if (widget.controller == null) unawaited(_start());
  }

  void _changed() {
    files.setDirty(c.dirty);
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    await c.initialize();
    if (c.ready) await c.load('{}', fresh: true, markSaved: false);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    files.dispose();
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    if (!c.dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Save your changes?'),
        content: Text('Unsaved changes to ${c.filename} will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text('Discard changes'),
          ),
          FilledButton(
            onPressed: c.canSave ? () => Navigator.pop(context, 'save') : null,
            child: Text('Save changes'),
          ),
        ],
      ),
    );
    if (choice == 'save') return _save();
    return choice == 'discard';
  }

  Future<void> _new() async {
    if (fileBusy ||
        c.busy ||
        c.validating ||
        c.canvasDraft ||
        !await _confirmDiscard()) {
      return;
    }
    if (await c.load('{}', fresh: true, markSaved: false)) files.reset();
  }

  Future<void> _open() async {
    if (fileBusy ||
        c.busy ||
        c.validating ||
        c.canvasDraft ||
        !await _confirmDiscard()) {
      return;
    }
    setState(() => fileBusy = true);
    try {
      final picked = await files.open();
      if (picked != null &&
          await c.load(
            picked['text'] as String,
            name: picked['name'] as String,
          )) {
        files.adopt();
      }
    } catch (e) {
      if (!e.toString().contains('AbortError')) {
        c.note('Could not open project: $e');
      }
    } finally {
      if (mounted) setState(() => fileBusy = false);
    }
  }

  Future<bool> _save({bool saveAs = false}) async {
    if (fileBusy || !c.canSave) return false;
    final raw = c.canonical;
    setState(() => fileBusy = true);
    try {
      final saved = await files.save(raw, c.filename, saveAs);
      if (saved['download'] == true) {
        c.note(
          'Download requested. Confirm it was saved before discarding this project.',
        );
        return false;
      }
      c.markSaved(raw, saved['name'] as String);
      return true;
    } catch (e) {
      if (!e.toString().contains('AbortError')) {
        c.note('Save failed; your project is still open. $e');
      }
      return false;
    } finally {
      if (mounted) setState(() => fileBusy = false);
    }
  }

  Future<void> _sample(String sample) async {
    if (fileBusy ||
        c.busy ||
        c.validating ||
        c.canvasDraft ||
        !await _confirmDiscard()) {
      return;
    }
    setState(() => fileBusy = true);
    try {
      final raw = await rootBundle.loadString('assets/phase08-$sample.json');
      if (await c.load(raw, name: '$sample.dungeon.json', markSaved: false)) {
        files.reset();
      }
    } catch (e) {
      c.note('Could not open example: $e');
    } finally {
      if (mounted) setState(() => fileBusy = false);
    }
  }

  Future<void> _rename() async {
    final text = TextEditingController(text: c.source['name'] as String? ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Project name'),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 80,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: Text('Rename'),
          ),
        ],
      ),
    );
    if (name != null) c.rename(name);
    // Dialog's exit animation retains the field briefly.
    await Future<void>.delayed(Duration(milliseconds: 250));
    text.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
          unawaited(_save()),
      SingleActivator(
        LogicalKeyboardKey.keyS,
        control: true,
        shift: true,
      ): () =>
          unawaited(_save(saveAs: true)),
      SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
          unawaited(_open()),
      SingleActivator(LogicalKeyboardKey.keyN, control: true, alt: true): () =>
          unawaited(_new()),
      SingleActivator(LogicalKeyboardKey.f5): () => unawaited(c.run()),
      SingleActivator(LogicalKeyboardKey.escape): () => unawaited(c.cancel()),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxWidth < 980, narrow = box.maxWidth < 700;
              return Column(
                children: [
                  _menubar(narrow),
                  _viewTabs(narrow),
                  Expanded(
                    child: Row(
                      children: [
                        if (!narrow)
                          SizedBox(
                            width: compact ? 180 : 218,
                            child: _explorer(),
                          ),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(child: _workspace()),
                              if (console && box.maxHeight > 560)
                                _console(narrow),
                            ],
                          ),
                        ),
                        if (!compact && inspector)
                          SizedBox(width: 268, child: _inspector()),
                      ],
                    ),
                  ),
                  _status(narrow),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  Widget _menubar(bool narrow) => Container(
    height: 43,
    decoration: BoxDecoration(
      color: panel,
      border: Border(bottom: BorderSide(color: line)),
    ),
    padding: EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        Icon(Icons.grid_view_rounded, color: violet, size: 19),
        SizedBox(width: 9),
        Text(
          'DUNGEON ARCHITECT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(width: 20),
        PopupMenuButton<String>(
          tooltip: 'Project commands',
          onSelected: (v) {
            switch (v) {
              case 'new':
                unawaited(_new());
              case 'open':
                unawaited(_open());
              case 'save':
                unawaited(_save());
              case 'saveAs':
                unawaited(_save(saveAs: true));
              case 'teaching':
                unawaited(_sample('teaching'));
              case 'standard':
                unawaited(_sample('standard-14'));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'new',
              enabled: !c.busy && !c.validating && !fileBusy && !c.canvasDraft,
              child: Text('New project        Ctrl+Alt+N'),
            ),
            PopupMenuItem(
              value: 'open',
              enabled: !c.busy && !c.validating && !fileBusy && !c.canvasDraft,
              child: Text('Open…                  Ctrl+O'),
            ),
            PopupMenuItem(
              value: 'save',
              enabled: c.canSave && !fileBusy,
              child: Text('Save                      Ctrl+S'),
            ),
            PopupMenuItem(
              value: 'saveAs',
              enabled: c.canSave && !fileBusy,
              child: Text('Save as…         Ctrl+Shift+S'),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'teaching',
              enabled: !c.busy && !c.validating && !fileBusy && !c.canvasDraft,
              child: Text('Open teaching example'),
            ),
            PopupMenuItem(
              value: 'standard',
              enabled: !c.busy && !c.validating && !fileBusy && !c.canvasDraft,
              child: Text('Open 14-pack example'),
            ),
          ],
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Text(
              c.dirty ? 'File •' : 'File',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ),
        if (!narrow)
          TextButton(
            onPressed: () => setState(() => console = !console),
            child: Text('Console'),
          ),
        Spacer(),
        if (!narrow)
          Text(
            'LOCAL WORKSPACE',
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 10,
              color: muted,
              letterSpacing: .8,
            ),
          ),
        SizedBox(width: 12),
        IconButton(
          tooltip: colors.dark ? 'Switch to light mode' : 'Switch to dark mode',
          onPressed: widget.onThemeToggle,
          icon: Icon(
            colors.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
        ),
        Lantern(),
      ],
    ),
  );
  List<Widget> _runActions(bool narrow) => [
    if (!c.ready && c.state == RunState.failed)
      OutlinedButton(onPressed: _start, child: Text('Retry connection'))
    else if (c.busy)
      OutlinedButton.icon(
        onPressed: c.state == RunState.cancelling ? null : c.cancel,
        icon: Icon(Icons.stop_rounded, size: 16),
        label: Text(c.state == RunState.cancelling ? 'Cancelling' : 'Cancel'),
      )
    else
      Tooltip(
        message: 'Automatically find a valid layout, connect rooms and solve allocation (F5)',
        child: FilledButton.icon(
          onPressed:
              c.canRun &&
                  !fileBusy &&
                  c.activePackCount <= ProjectController.exactPackLimit
              ? () => c.run()
              : null,
          icon: Icon(Icons.play_arrow_rounded, size: 17),
          label: Text(narrow ? 'Run' : 'Generate & solve'),
        ),
      ),
    if (!c.busy && MediaQuery.sizeOf(context).width >= 1100) ...[
      TextButton(
        onPressed: c.canRun && !fileBusy
            ? () => c.run(geometryOnly: true)
            : null,
        child: Text('Generate only'),
      ),
      TextButton(
        onPressed: c.canOptimize && !fileBusy ? c.optimize : null,
        child: Text('Optimize'),
      ),
    ],
    IconButton(
      tooltip: 'Project inspector',
      onPressed: () {
        if (MediaQuery.sizeOf(context).width < 980) {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => SizedBox(
              height: MediaQuery.sizeOf(context).height * .8,
              child: AnimatedBuilder(
                animation: c,
                builder: (_, _) => _inspector(),
              ),
            ),
          );
        } else {
          setState(() => inspector = !inspector);
        }
      },
      icon: Icon(Icons.tune_rounded),
    ),
  ];
  Widget _explorer() => Container(
    decoration: BoxDecoration(
      color: panel,
      border: Border(right: BorderSide(color: line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelHeading('Explorer'),
        Padding(
          padding: EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.filename,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11),
              ),
              Text(
                c.dirty ? 'Unsaved source changes' : 'All source changes saved',
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(12, 16, 10, 12),
          child: Row(
            children: [
              Icon(Icons.keyboard_arrow_down, size: 16),
              SizedBox(width: 4),
              Icon(Icons.folder_outlined, size: 17, color: violet),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  c.source['name'] as String? ?? 'Workspace',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        _treeLabel(
          Icons.crop_free,
          'Allowed area',
          '${c.settings['columns'] ?? '—'} × ${c.settings['rows'] ?? '—'}',
        ),
        _treeLabel(
          Icons.meeting_room_outlined,
          'Rooms',
          '${c.editableRooms.length}',
        ),
        Expanded(
          child: c.editableRooms.isEmpty
              ? Padding(
                  padding: EdgeInsets.fromLTRB(32, 12, 20, 0),
                  child: Text(
                    'Generated rooms will appear here.',
                    style: TextStyle(fontSize: 11, color: muted, height: 1.6),
                  ),
                )
              : ListView.builder(
                  itemCount: c.editableRooms.length,
                  itemBuilder: (context, i) {
                    final r = c.editableRooms[i];
                    final selected = c.selectedRoom == r['id'];
                    return Padding(
                      padding: EdgeInsets.only(left: 20, right: 8),
                      child: Material(
                        color: selected ? lavender : Colors.transparent,
                        child: InkWell(
                          onTap: () => c.select(r['id'] as String),
                          child: Container(
                            height: 31,
                            padding: EdgeInsets.symmetric(horizontal: 9),
                            child: Row(
                              children: [
                                Icon(
                                  r['role'] == 'entrance'
                                      ? Icons.login
                                      : r['role'] == 'exit'
                                      ? Icons.logout
                                      : Icons.crop_square,
                                  size: 14,
                                  color: selected ? violet : muted,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    r['name'].toString().isEmpty
                                        ? r['id']
                                        : r['name'],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: selected ? violet : ink,
                                    ),
                                  ),
                                ),
                                if (c.roomFixed(r['id'] as String))
                                  Icon(Icons.lock_outline, size: 11),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Divider(),
        _treeLabel(
          Icons.hexagon_outlined,
          'Encounter inventory',
          '${(c.source['packs'] as List? ?? []).length}',
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Text(
            '${(c.source['packs'] as List? ?? []).where((p) => p['active'] == true).length} active packs · exact solver',
            style: TextStyle(fontSize: 10, color: muted),
          ),
        ),
        Container(
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: line)),
          ),
          child: Row(
            children: [
              Icon(Icons.eco_outlined, size: 15, color: moss),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'A little order in the labyrinth.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _treeLabel(IconData icon, String text, String count) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 9),
    child: Row(
      children: [
        Icon(icon, size: 15),
        SizedBox(width: 9),
        Expanded(child: Text(text, style: TextStyle(fontSize: 11))),
        Text(
          count,
          style: TextStyle(fontFamily: 'Consolas', fontSize: 10, color: muted),
        ),
      ],
    ),
  );
  Widget _viewTabs(bool narrow) => Container(
    height: 44,
    decoration: BoxDecoration(
      color: panel,
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        for (final view in EditorView.values)
          Tooltip(
            message: '${view.name} workspace',
            child: InkWell(
              onTap: () => c.switchView(view),
              child: Container(
                width: narrow ? 74 : 108,
                height: 40,
                decoration: BoxDecoration(
                  color: c.view == view ? paper : Colors.transparent,
                  border: Border(
                    top: BorderSide(
                      color: c.view == view ? violet : Colors.transparent,
                      width: 2,
                    ),
                    right: BorderSide(color: line),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      [
                        Icons.architecture_outlined,
                        Icons.account_tree_outlined,
                        Icons.sports_esports_outlined,
                      ][view.index],
                      size: 15,
                      color: c.view == view ? violet : muted,
                    ),
                    SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        ['Design', 'Analyze', 'Play'][view.index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: c.view == view ? ink : muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Spacer(),
        ..._runActions(narrow),
        IconButton(
          tooltip: 'Toggle grid',
          onPressed: () => setState(() => grid = !grid),
          icon: Icon(Icons.grid_4x4, size: 16, color: grid ? violet : muted),
        ),
      ],
    ),
  );
  Widget _workspace() => ColoredBox(
    color: colors.canvas,
    child: Column(
      children: [
        Container(
          height: 35,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                c.view == EditorView.design
                    ? 'DESIGN CANVAS'
                    : c.view == EditorView.analyze
                    ? 'ALLOCATION OVERVIEW'
                    : 'EXPLORATION PREVIEW',
                style: TextStyle(fontSize: 10, letterSpacing: 1, color: muted),
              ),
              Spacer(),
              if (c.stale) _badge('STALE · previous result', Color(0xFF946322)),
              if (!c.stale && c.result != null) _badge('VERIFIED', moss),
              SizedBox(width: 12),
              Text(
                'TILES',
                style: TextStyle(
                  fontSize: 10,
                  color: muted,
                  fontFamily: 'Consolas',
                ),
              ),
            ],
          ),
        ),
        if (c.view == EditorView.analyze)
          Container(
            width: double.infinity,
            color: panel,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analyze · inspect the solved encounter allocation and engine work.',
                  style: TextStyle(fontSize: 12, color: ink),
                ),
                SizedBox(height: 5),
                Text(
                  c.allocation == null
                      ? 'Generate a layout first to see score, threat usage and placed actors.'
                      : '${c.stale ? 'Previous result · ' : ''}${c.rooms.length} rooms · Score ${c.allocation!['total_score']} · Threat ${c.allocation!['total_threat']} · ${(c.allocation!['actors'] as List).length} actors',
                  style: TextStyle(fontSize: 11, color: violet),
                ),
                Text(
                  'Select rooms to inspect them. Engine counters appear in the console; step-by-step algorithm playback is not available yet.',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
        if (c.view == EditorView.play)
          Container(
            width: double.infinity,
            color: colors.panel,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Play · map preview only. Inspect the entrance, exit and connected floor. Player movement is not implemented yet.${c.stale ? ' Generate again to refresh this map.' : ''}',
              style: TextStyle(fontSize: 11, color: moss),
            ),
          ),
        Expanded(
          child: DungeonPreview(
            key: ValueKey(c.documentEpoch),
            controller: c,
            grid: grid,
          ),
        ),
        Container(
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: line)),
          ),
          child: Row(
            children: [
              _legend(moss, 'Entrance'),
              SizedBox(width: 18),
              _legend(violet, 'Exit'),
              SizedBox(width: 18),
              _legend(Color(0xFF9388A0), 'Room'),
              Spacer(),
              Text(
                c.selectedRoom ?? 'No room selected',
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _legend(Color color, String label) => Row(
    children: [
      Container(width: 6, height: 6, color: color),
      SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 10, color: muted)),
    ],
  );
  Widget _badge(String text, Color color) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Consolas',
      fontSize: 10,
      color: color,
      fontWeight: FontWeight.w600,
    ),
  );
  Widget _inspector() => Container(
    decoration: BoxDecoration(
      color: paper,
      border: Border(left: BorderSide(color: line)),
    ),
    child: Column(
      children: [
        PanelHeading('Inspector'),
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Text(
                    'Project',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Spacer(),
                  IconButton(
                    tooltip: 'Rename project',
                    onPressed:
                        c.document != null &&
                            !fileBusy &&
                            !c.loading &&
                            !c.canvasDraft
                        ? _rename
                        : null,
                    icon: Icon(Icons.edit_outlined, size: 15),
                  ),
                ],
              ),
              Text(
                c.source['name'] as String? ?? 'Connecting…',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              if (c.selectedRoom != null) ...[
                SizedBox(height: 22),
                Divider(),
                SizedBox(height: 18),
                Text(
                  'SELECTION',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: muted,
                  ),
                ),
                SizedBox(height: 12),
                ..._selection(),
              ],
              SizedBox(height: 22),
              Text(
                'GENERATION',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: muted,
                ),
              ),
              SizedBox(height: 14),
              _number(
                'Room count',
                'room_count',
                'rooms',
                2,
                (c.settings['columns'] as int? ?? 150) *
                    (c.settings['rows'] as int? ?? 150),
              ),
              _number('Seed', 'seed', 'seed', 0, 4294967295),
              _number('Min room width', 'min_room_width', 'tiles', 1, 512),
              _number('Max room width', 'max_room_width', 'tiles', 1, 512),
              _number('Min room height', 'min_room_height', 'tiles', 1, 512),
              _number('Max room height', 'max_room_height', 'tiles', 1, 512),
              _number('Corridor width', 'corridor_width', 'tiles', 1, 512),
              _number('Room margin', 'margin', 'tiles', 0, 512),
              Text(
                'Starting seed. Generate searches automatically and saves the first successful seed.',
                style: TextStyle(fontSize: 11, color: muted, height: 1.5),
              ),
              SizedBox(height: 14),
              Divider(),
              SizedBox(height: 18),
              Text(
                'ALLOCATION',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: muted,
                ),
              ),
              SizedBox(height: 14),
              _number('Threat budget', 'threat_budget', 'points', 0, null),
              Text(
                c.result == null
                    ? 'Generate a dungeon to begin.'
                    : c.geometryCurrent
                    ? 'Geometry current · Optimize refreshes allocation.'
                    : 'Geometry stale · Generate to recompute rooms and corridors.',
                style: TextStyle(fontSize: 11, color: violet),
              ),
              SizedBox(height: 12),
              Wrap(
                children: [
                  TextButton(
                    onPressed: c.canRun
                        ? () => c.run(geometryOnly: true)
                        : null,
                    child: Text('Generate only'),
                  ),
                  TextButton(
                    onPressed: c.canOptimize ? c.optimize : null,
                    child: Text('Optimize'),
                  ),
                ],
              ),
              EncounterCatalogue(controller: c),
              Text(
                'Exact subset optimization. Unselected packs remain in the inventory.',
                style: TextStyle(fontSize: 11, color: muted, height: 1.6),
              ),
              SizedBox(height: 18),
              Text(
                'KEEP A ROOM IN PLACE',
                style: TextStyle(
                  fontSize: 10,
                  color: muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 6),
              Text(
                '1. Generate a layout.\n2. Use Select room, then click a room or its Explorer entry.\n3. Choose Fix room here in Selection. Its position and size are preserved on later runs.',
                style: TextStyle(fontSize: 11, color: muted, height: 1.6),
              ),
              if (c.allocation != null) ...[
                SizedBox(height: 22),
                Divider(),
                SizedBox(height: 18),
                Text(
                  c.stale ? 'PREVIOUS RESULT' : 'RESULT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: muted,
                  ),
                ),
                SizedBox(height: 12),
                _property('Rooms', '${c.rooms.length}'),
                _property(
                  'Score',
                  '${c.payload!['allocation']['total_score']}',
                ),
                _property(
                  'Threat used',
                  '${c.payload!['allocation']['total_threat']}',
                ),
                _property(
                  'Placed actors',
                  '${(c.payload!['allocation']['actors'] as List).length}',
                ),
                _property('Slots used', '${c.allocation!['total_slots']}'),
                for (final unused in c.allocation!['unused'] as List? ?? [])
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Unused ${unused['pack_id']}: ${unused['reason']}',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
  Widget _number(
    String label,
    String key,
    String unit,
    int min,
    int? max,
  ) => NumericField(
    key: ValueKey('${c.documentEpoch}:$key'),
    label: label,
    value: '${c.settingValue(key) ?? ''}',
    unit: unit,
    error: c.fieldErrors[key],
    enabled: c.document != null && !fileBusy && !c.loading && !c.canvasDraft,
    onChanged: (value) => c.editSetting(
      key,
      value,
      min: BigInt.from(min),
      max: max == null ? BigInt.parse('9223372036854775807') : BigInt.from(max),
    ),
  );
  List<Widget> _selection() {
    final matching = c.editableRooms.where((r) => r['id'] == c.selectedRoom);
    if (matching.isEmpty) return [];
    final r = matching.first, b = r['bounds'];
    return [
      _property('ID', r['id']),
      _property('Role', r['role']),
      _property('Interior', '${b['width']} × ${b['height']}'),
      _property('Origin', '${b['x']}, ${b['y']}'),
      _property('Name', '${r['name']}'),
      _property('Tags', (r['tags'] as List? ?? []).join(', ')),
      if (c.payload != null) ...[
        for (final p in c.payload!['geometry']?['rooms'] as List? ?? [])
          if (p['id'] == r['id']) ...[
            _property(
              'Valid positions',
              '${(p['spawn_positions'] as List).length}',
            ),
            _property(
              'Capacity',
              '${r['capacity_override'] ?? p['capacity']} slots',
            ),
          ],
      ],
      for (final assignment in c.allocation?['assignments'] as List? ?? [])
        if (assignment['room_id'] == r['id'])
          _property('Assigned pack', '${assignment['pack_id']}'),
      if (c.allocation != null)
        _property(
          'Slots used',
          '${(c.allocation!['actors'] as List).where((a) => a['room_id'] == r['id']).length}',
        ),
      OutlinedButton(
        onPressed: c.canRun
            ? () => editRoom(context, c, Map<String, dynamic>.from(r as Map))
            : null,
        child: Text('Edit room details'),
      ),
      if ((c.source['rooms'] as List? ?? []).any(
        (room) => room['id'] == r['id'],
      )) ...[
        OutlinedButton(
          onPressed: c.canRun && c.selectedRoomFixed
              ? () => c.unlockRoom(r['id'] as String)
              : null,
          child: Text('Unlock room'),
        ),
        TextButton(
          onPressed: c.canRun && !c.selectedRoomFixed
              ? () => c.removeRoom(r['id'] as String)
              : null,
          child: Text('Remove room'),
        ),
      ],
      SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: c.canRun && (c.selectedRoomFixed || !c.stale)
            ? () => c.setRoomFixed(!c.selectedRoomFixed)
            : null,
        icon: Icon(
          c.selectedRoomFixed ? Icons.lock_open : Icons.push_pin_outlined,
          size: 16,
        ),
        label: Text(c.selectedRoomFixed ? 'Release room' : 'Fix room here'),
      ),
      Text(
        c.selectedRoomFixed
            ? 'Fixed position and size. Release to allow regeneration.'
            : c.stale
            ? 'Generate a current layout before fixing this room.'
            : 'Other rooms will generate around this room.',
        style: TextStyle(fontSize: 11, color: muted),
      ),
    ];
  }

  Widget _property(String label, String value) => Padding(
    padding: EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: muted)),
        Spacer(),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Consolas', fontSize: 11),
          ),
        ),
      ],
    ),
  );
  Widget _console(bool narrow) => Container(
    height: 126,
    decoration: BoxDecoration(
      color: paper,
      border: Border(top: BorderSide(color: line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelHeading(
          c.view == EditorView.analyze ? 'Run summary' : 'Output',
          trailing: TextButton(
            onPressed: () => setState(() => console = false),
            child: Text('Hide', style: TextStyle(fontSize: 10)),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.view == EditorView.analyze && c.result != null)
                  Text(
                    'Generation ${c.result!.document['stages']?['generation']?['metrics']?['work_units'] ?? '—'} work units   /   Routing ${c.result!.document['stages']?['routing']?['metrics']?['work_units'] ?? '—'}   /   DP ${c.result!.document['stages']?['allocation']?['metrics']?['transitions'] ?? '—'} transitions',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 11,
                      color: violet,
                    ),
                  ),
                for (final entry in c.log.take(4))
                  Padding(
                    padding: EdgeInsets.only(bottom: 5),
                    child: Text(
                      '›  $entry',
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11,
                        color: entry == c.message ? ink : muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Widget _status(bool narrow) => Container(
    height: 28,
    color: colors.panel,
    padding: EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        Icon(
          c.state == RunState.invalid || c.state == RunState.failed
              ? Icons.warning_amber_rounded
              : c.busy
              ? Icons.hourglass_bottom
              : Icons.circle,
          size: 11,
          color: c.state == RunState.failed ? Color(0xFFA44242) : moss,
        ),
        SizedBox(width: 7),
        Expanded(
          child: Text(
            c.validating
                ? 'Validating project…'
                : c.busy
                ? '${c.state == RunState.cancelling ? 'Cancelling' : c.stage} · rev ${c.activeRevision}'
                : c.message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: ink),
          ),
        ),
        if (!narrow) ...[
          SizedBox(width: 16),
          Text(
            'rev ${c.revision}',
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 10,
              color: muted,
            ),
          ),
          SizedBox(width: 18),
          Text(
            'C++ · WebAssembly',
            style: TextStyle(fontSize: 10, color: muted),
          ),
        ],
      ],
    ),
  );
}
