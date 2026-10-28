import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/engine.dart';
import 'exact_json.dart';
import 'analysis_controller.dart';
import 'scenario_controller.dart';
import 'play_controller.dart';

enum EditorView { design, analyze, play }

enum RunState { idle, running, cancelling, successful, stale, invalid, failed }

class ProjectController extends ChangeNotifier {
  ProjectController({Engine? engine, Engine? validator})
    : engine = engine ?? Engine(),
      validator = validator ?? Engine() {
    scenario = ScenarioController(() => this.engine);
    play = PlayController(
      ({
        required snapshotJob,
        required x,
        required y,
        required dx,
        required dy,
      }) => this.engine.step(
        snapshotJob: snapshotJob,
        x: x,
        y: y,
        dx: dx,
        dy: dy,
      ),
    );
    scenario.addListener(_scenarioChanged);
    playback.addListener(_notify);
    benchmarks.addListener(_notify);
  }
  Engine engine, validator;
  late final ScenarioController scenario;
  late final PlayController play;
  void _scenarioChanged() {
    play.invalidate();
    _notify();
  }

  final TracePlayback playback = TracePlayback();
  final BenchmarkController benchmarks = BenchmarkController();
  Map<String, dynamic> analysisMetrics = {};
  final Set<String> overlays = {'mask', 'room IDs', 'assignments'};
  int? selectedPartition;
  String analysisOutcome = 'No completed run';
  void toggleOverlay(String key) {
    if (!overlays.add(key)) overlays.remove(key);
    _notify();
  }

  void selectPartition(int? value) {
    selectedPartition = value;
    _notify();
  }

  Future<void> _captureAnalysis(EngineResult attempt, int stamp) async {
    try {
      final metric = await engine.metrics();
      final events = <Map<String, dynamic>>[];
      var cursor = 0, dropped = 0, runId = 0;
      var truncated = false;
      while (events.length < TracePlayback.maxEvents) {
        final batch = await engine.trace(cursor: cursor);
        if (disposed || stamp != revision) return;
        runId = batch['run_id'] as int? ?? batch['job'] as int? ?? 0;
        for (final raw in batch['events'] as List? ?? []) {
          final event = Map<String, dynamic>.from(raw as Map)
            ..['editor_revision'] = stamp;
          events.add(event);
        }
        dropped = batch['dropped_events'] as int? ?? 0;
        truncated = batch['truncated'] == true;
        final next = batch['next_cursor'] as int? ?? cursor;
        if (next == cursor || next >= (batch['total'] as int? ?? 0)) break;
        cursor = next;
      }
      if (disposed || stamp != revision) return;
      analysisMetrics = metric;
      analysisOutcome =
          '${attempt.document['outcome']} · ${attempt.document['optimal'] == true ? 'exact allocation verified' : 'no optimality claim'}';
      playback.load(
        events,
        revision: stamp,
        runId: runId,
        truncated: truncated,
        dropped: dropped,
      );
      _notify();
    } catch (e) {
      if (!disposed && stamp == revision) {
        analysisOutcome = "Trace unavailable: $e";
        playback.load([], revision: stamp, runId: 0);
        _notify();
      }
    }
  }

  int documentEpoch = 0;
  Map<String, dynamic>? document;
  String canonical = '', filename = 'untitled.dungeon.json';
  String? saved;
  int revision = 0,
      validatedRevision = -1,
      resultRevision = -1,
      activeRevision = -1;
  int geometryRevision = 0, allocationRevision = 0;
  int resultGeometryRevision = -1;
  static const exactPackLimit = 14;
  String? selectedRoom;
  EditorView view = EditorView.design;
  RunState state = RunState.idle;
  String message = 'Connecting to the engine…';
  String stage = '';
  bool ready = false, validating = false, loading = false, disposed = false;
  EngineResult? result;
  Map<String, dynamic> editorAnalysis = {};
  bool canvasDraft = false;
  final Map<String, String> fieldErrors = {};
  Map<String, dynamic>? _settingsDraft;
  final Set<String> _settingsValidationErrors = {};
  final List<String> log = [];
  Future<void> _queue = Future.value();
  Timer? _timer;
  int searchAttempt = 0;
  bool get busy => state == RunState.running || state == RunState.cancelling;
  bool get dirty =>
      document != null &&
      (canonical != saved ||
          validatedRevision != revision ||
          fieldErrors.isNotEmpty);
  bool get stale => result != null && resultRevision != revision;
  bool get canRun =>
      ready &&
      document != null &&
      !validating &&
      !canvasDraft &&
      !busy &&
      !scenario.busy &&
      fieldErrors.isEmpty &&
      validatedRevision == revision;
  bool get canSave =>
      document != null &&
      !validating &&
      !canvasDraft &&
      fieldErrors.isEmpty &&
      validatedRevision == revision;
  Map<String, dynamic> get source =>
      document?['source'] as Map<String, dynamic>? ?? {};
  Map<String, dynamic> get settings =>
      source['settings'] as Map<String, dynamic>? ?? {};
  dynamic settingValue(String key) {
    const ranges = {
      'min_room_width': ('room_width', 0),
      'max_room_width': ('room_width', 1),
      'min_room_height': ('room_height', 0),
      'max_room_height': ('room_height', 1),
    };
    final range = ranges[key];
    return range == null
        ? settings[key]
        : (settings[range.$1] as List?)?[range.$2];
  }

  Map<String, dynamic>? get payload =>
      result?.document['result'] as Map<String, dynamic>?;
  List<dynamic> get rooms =>
      payload?['layout']?['rooms'] as List<dynamic>? ?? [];
  List<dynamic> get catalogue => source['packs'] as List? ?? [];
  int get activePackCount => catalogue.where((p) => p['active'] == true).length;
  bool get geometryCurrent =>
      result != null && resultGeometryRevision == geometryRevision;
  bool get canOptimize =>
      canRun && geometryCurrent && activePackCount <= exactPackLimit;
  Map<String, dynamic>? get allocation =>
      payload?['allocation'] as Map<String, dynamic>?;
  List<dynamic> get editableRooms {
    final byId = <String, dynamic>{for (final r in rooms) r['id'] as String: r};
    for (final r in source['rooms'] as List? ?? []) {
      byId[r['id'] as String] = r;
    }
    return byId.values.toList();
  }

  String _nextId(String prefix, Iterable<dynamic> records) {
    final ids = records.map((r) => r['id']).toSet();
    var n = 1;
    while (ids.contains('$prefix-$n')) {
      n++;
    }
    return '$prefix-$n';
  }

  String nextRoomId() => _nextId('room', editableRooms);
  String nextPackId() => _nextId('pack', catalogue);
  void _notify() {
    if (scenario.revision != revision ||
        !identical(scenario.baseline, result)) {
      scenario.bind(result, revision, engine.snapshotJob);
      play.invalidate();
    }
    if (view != EditorView.play || busy || validating || canvasDraft) {
      play.pause();
    }
    if (playback.playing &&
        (playback.revision != revision || view != EditorView.analyze)) {
      playback.pause();
    }
    if (!disposed) notifyListeners();
  }

  void note(String text) {
    message = text;
    log.insert(0, text);
    if (log.length > 40) log.removeLast();
    _notify();
  }

  Future<void> initialize() async {
    try {
      if (engine.closed || validator.closed) {
        await Future.wait([engine.close(), validator.close()]);
        engine = Engine();
        validator = Engine();
      }
      await Future.wait([engine.open(), validator.open()]);
      ready = true;
      note('Engine ready.');
    } catch (e) {
      state = RunState.failed;
      note('$e');
    }
  }

  Future<EngineResult> _normalize(String raw, {bool fresh = false}) => _request(
    raw,
    fresh ? EngineOperation.newProject : EngineOperation.normalize,
  );

  Future<EngineResult> _request(String raw, EngineOperation operation) {
    final done = Completer<EngineResult>();
    _queue = _queue.then((_) async {
      if (disposed) {
        done.completeError(StateError('Editor closed.'));
        return;
      }
      try {
        done.complete(
          await validator.run(raw, operation: operation, maxEvents: 0),
        );
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  String _problem(EngineResult r) {
    final diagnostics = r.document['diagnostics'] as List? ?? [];
    return diagnostics.isEmpty
        ? '${r.document['outcome']}'
        : '${diagnostics.first['message']} ${diagnostics.first['recovery'] ?? ''}';
  }

  Future<bool> load(
    String raw, {
    String name = 'untitled.dungeon.json',
    bool fresh = false,
    bool markSaved = true,
  }) async {
    if (busy || validating || canvasDraft) return false;
    loading = true;
    validating = true;
    _notify();
    try {
      final checked = await _normalize(raw, fresh: fresh);
      if (disposed) return false;
      if (!checked.succeeded) {
        note('Open failed: ${_problem(checked)}');
        return false;
      }
      final text = checked.document['project_json'] as String;
      final next = decodeExact(text) as Map<String, dynamic>;
      document = next;
      editorAnalysis =
          checked.document['editor_analysis'] as Map<String, dynamic>? ?? {};
      documentEpoch++;
      canonical = text;
      saved = markSaved ? text : null;
      filename = name;
      revision++;
      geometryRevision++;
      allocationRevision++;
      validatedRevision = revision;
      result = null;
      playback.load([], revision: revision, runId: 0);
      analysisMetrics = {};
      analysisOutcome = "No completed run";
      selectedPartition = null;
      resultRevision = -1;
      resultGeometryRevision = -1;
      selectedRoom = null;
      fieldErrors.clear();
      _settingsDraft = null;
      _settingsValidationErrors.clear();
      state = RunState.idle;
      note(
        fresh ? 'New project. Generate a layout to begin.' : 'Opened $name.',
      );
      return true;
    } catch (e) {
      note('Open failed: $e');
      return false;
    } finally {
      loading = false;
      validating = false;
      _notify();
    }
  }

  void switchView(EditorView value) {
    if (value != EditorView.analyze) playback.pause();
    view = value;
    _notify();
  }

  void select(String? id) {
    selectedRoom = id;
    _notify();
  }

  void editSetting(
    String key,
    String text, {
    required BigInt min,
    required BigInt max,
  }) {
    if (document == null || loading || canvasDraft) return;
    final value = RegExp(r'^\d+$').hasMatch(text)
        ? BigInt.tryParse(text)
        : null;
    revision++;
    allocationRevision++;
    if (key != 'threat_budget') geometryRevision++;
    if (value == null || value < min || value > max) {
      validating = false;
      fieldErrors[key] = 'Enter a whole number from $min to $max.';
      if (!busy) state = RunState.invalid;
      note('Check the highlighted project settings.');
      return;
    }
    fieldErrors.remove(key);
    final candidate = decodeExact(
      encodeExact(_settingsDraft ?? decodeExact(canonical)),
    ) as Map<String, dynamic>;
    final number = value <= BigInt.from(9007199254740991)
        ? value.toInt()
        : value;
    const ranges = {
      'min_room_width': ('room_width', 0),
      'max_room_width': ('room_width', 1),
      'min_room_height': ('room_height', 0),
      'max_room_height': ('room_height', 1),
    };
    final range = ranges[key];
    if (range == null) {
      candidate['source']['settings'][key] = number;
    } else {
      candidate['source']['settings'][range.$1][range.$2] = number;
    }
    _settingsDraft = candidate;
    if (!busy) state = result == null ? RunState.idle : RunState.stale;
    _validateDraft(candidate: candidate, settingKey: key);
  }

  void rename(String name) {
    if (document == null || loading || canvasDraft || source['name'] == name) {
      return;
    }
    final candidate = decodeExact(
      encodeExact(_settingsDraft ?? document),
    ) as Map<String, dynamic>;
    candidate['source']['name'] = name;
    _settingsDraft = candidate;
    revision++;
    if (!busy) state = result == null ? RunState.idle : RunState.stale;
    _validateDraft(candidate: candidate);
  }

  void _validateDraft({Map<String, dynamic>? candidate, String? settingKey}) {
    final stamp = revision, raw = encodeExact(candidate ?? document);
    validating = true;
    _notify();
    _normalize(raw)
        .then((checked) {
          if (disposed || revision != stamp) return;
          if (checked.succeeded) {
            for (final key in _settingsValidationErrors) {
              fieldErrors.remove(key);
            }
            _settingsValidationErrors.clear();
            _settingsDraft = null;
            canonical = checked.document['project_json'] as String;
            document = decodeExact(canonical) as Map<String, dynamic>;
            editorAnalysis =
                checked.document['editor_analysis'] as Map<String, dynamic>? ??
                {};
            validatedRevision = stamp;
            if (!busy) {
              state = fieldErrors.isNotEmpty
                  ? RunState.invalid
                  : result == null
                  ? RunState.idle
                  : RunState.stale;
            }
            message = fieldErrors.isEmpty
                ? 'Settings updated. Run to refresh the result.'
                : 'Check the highlighted settings.';
          } else {
            if (settingKey != null) {
              fieldErrors[settingKey] = _problem(checked);
              _settingsValidationErrors.add(settingKey);
            }
            if (!busy) state = RunState.invalid;
            message = _problem(checked);
          }
        })
        .catchError((Object e) {
          if (!disposed && revision == stamp) {
            if (!busy) state = RunState.failed;
            message = '$e';
          }
        })
        .whenComplete(() {
          if (!disposed && revision == stamp) {
            validating = false;
            _notify();
          }
        });
  }

  Future<void> run({bool geometryOnly = false}) async {
    if (!canRun) return;
    if (!geometryOnly && activePackCount > exactPackLimit) {
      note(
        'Exact optimization supports at most $exactPackLimit active packs. Deactivate catalogue entries or use Generate only.',
      );
      return;
    }
    final stamp = revision;
    activeRevision = stamp;
    playback.pause();
    state = RunState.running;
    searchAttempt = 0;
    final draft = decodeExact(canonical) as Map<String, dynamic>;
    final startSeed = settings['seed'] as int;
    final watch = Stopwatch()..start();
    // JSON permits int64 limits; browser timers only support signed int32 ms.
    final configuredMs = BigInt.parse('${settings['max_time_ms'] ?? 30000}');
    final timerMax = BigInt.from(2147483647);
    final limit = Duration(
      milliseconds: (configuredMs > timerMax ? timerMax : configuredMs).toInt(),
    );
    var timedOut = false;
    final deadline = Timer(limit, () {
      timedOut = true;
      unawaited(engine.cancel().catchError((Object _) {}));
    });
    note('Searching automatically for a valid layout…');
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!disposed) {
        stage = 'Candidate $searchAttempt · ${engine.progress.stageName}';
        _notify();
      }
    });
    try {
      EngineResult next;
      var winningSource = canonical;
      do {
        searchAttempt++;
        final seed = (startSeed + searchAttempt - 1) % 4294967296;
        draft['source']['settings']['seed'] = seed;
        winningSource = searchAttempt == 1 ? canonical : encodeExact(draft);
        next = geometryOnly
            ? await engine.run(
                winningSource,
                operation: EngineOperation.generateDungeon,
                maxEvents: 4096,
              )
            : await engine.run(
                winningSource,
                maxEvents: 4096,
                detailedTrace:
                    activePackCount <= 6 &&
                    (settings['room_count'] as int? ?? 0) <= 8,
              );
        if (disposed ||
            revision != stamp ||
            state == RunState.cancelling ||
            timedOut ||
            next.succeeded ||
            next.document['outcome'] != 'search_exhausted') {
          break;
        }
        // Yield between native jobs so Cancel and edits cannot be starved.
        await Future<void>.delayed(Duration.zero);
      } while (!disposed &&
          revision == stamp &&
          state != RunState.cancelling &&
          !timedOut &&
          watch.elapsed < limit &&
          searchAttempt < 1000);
      deadline.cancel();
      if (disposed) return;
      if (revision != stamp) {
        state = fieldErrors.isNotEmpty ? RunState.invalid : RunState.stale;
        note('Input changed during the run. Its result was not applied.');
      } else if (state == RunState.cancelling || timedOut) {
        analysisOutcome = timedOut
            ? 'search_exhausted - no optimality claim'
            : 'cancelled - no optimality claim';
        state = stale ? RunState.stale : RunState.idle;
        note(
          timedOut
              ? 'Search time limit reached after $searchAttempt candidates. No result replaced. Reduce room count or widen the allowed area.'
              : 'Cancelled. The last valid result was kept.',
        );
      } else if (next.succeeded) {
        if (searchAttempt > 1) {
          final checked = await _normalize(winningSource);
          if (disposed) return;
          if (revision != stamp || state == RunState.cancelling) {
            state = fieldErrors.isNotEmpty
                ? RunState.invalid
                : stale
                ? RunState.stale
                : RunState.idle;
            note('Search stopped. Its result was not applied.');
            return;
          }
          if (!checked.succeeded) throw StateError(_problem(checked));
          canonical = checked.document['project_json'] as String;
          document = decodeExact(canonical) as Map<String, dynamic>;
          editorAnalysis =
              checked.document['editor_analysis'] as Map<String, dynamic>? ??
              {};
          revision++;
          geometryRevision++;
          allocationRevision++;
          validatedRevision = revision;
        }
        final analysisStamp = revision;
        await _captureAnalysis(next, analysisStamp);
        if (disposed) return;
        if (revision != analysisStamp || state == RunState.cancelling) {
          state = stale ? RunState.stale : RunState.idle;
          note(
            'Input changed or cancelled while preparing analysis. Previous result retained.',
          );
          return;
        }
        result = next;
        resultRevision = revision;
        resultGeometryRevision = geometryRevision;
        state = RunState.successful;
        if (!rooms.any((r) => r['id'] == selectedRoom)) selectedRoom = null;
        note(
          'Completed. ${geometryOnly ? 'Geometry verified; Optimize to allocate encounters.' : 'Exact allocation verified.'} First valid solution after $searchAttempt candidate${searchAttempt == 1 ? '' : 's'}; seed ${settings['seed']}.',
        );
      } else {
        await _captureAnalysis(next, stamp);
        state = next.document['outcome'] == 'invalid_input'
            ? RunState.invalid
            : next.document['outcome'] == 'cancelled'
            ? (stale ? RunState.stale : RunState.idle)
            : RunState.failed;
        note(
          next.document['outcome'] == 'search_exhausted'
              ? 'No valid solution within $searchAttempt candidates. Reduce room count or widen the allowed area. ${_problem(next)}'
              : '${next.document['outcome']}: ${_problem(next)}',
        );
      }
    } catch (e) {
      if (!disposed) {
        state = RunState.failed;
        note('Run failed: $e');
      }
    } finally {
      deadline.cancel();
      _timer?.cancel();
      activeRevision = -1;
      stage = '';
      _notify();
    }
  }

  bool roomFixed(String? id) => (source['rooms'] as List? ?? []).any(
    (r) =>
        r['id'] == id && (r['lock_position'] == true || r['lock_size'] == true),
  );
  bool get selectedRoomFixed => roomFixed(selectedRoom);

  Future<bool> _editRecord(
    Map<String, dynamic> command, {
    bool geometry = false,
  }) async {
    if (!canRun) return false;
    final stamp = revision;
    setCanvasDraft(true);
    try {
      final checked = await previewCanvas(command);
      if (!checked.succeeded) {
        note('Edit rejected: ${_problem(checked)}');
        return false;
      }
      return commitCanvas(checked, stamp, geometry: geometry);
    } catch (e) {
      note('Edit failed: $e');
      return false;
    } finally {
      setCanvasDraft(false);
    }
  }

  Future<bool> savePack(Map<String, dynamic> pack) =>
      _editRecord({'type': 'upsert_pack', 'pack': pack});
  Future<bool> removePack(String id) =>
      _editRecord({'type': 'remove_pack', 'id': id});
  Future<bool> duplicatePack(String id) async {
    final matches = catalogue.where((p) => p['id'] == id);
    if (matches.isEmpty) return false;
    final pack =
        decodeExact(encodeExact(matches.first)) as Map<String, dynamic>;
    pack['id'] = nextPackId();
    pack['name'] = '${pack['name']} copy';
    return savePack(pack);
  }

  Future<bool> saveRoom(Map<String, dynamic> room) {
    final matches = (source['rooms'] as List? ?? []).where(
      (r) => r['id'] == room['id'],
    );
    final old = matches.isEmpty ? null : matches.first;
    final geometry =
        old == null ||
        encodeExact(old['bounds']) != encodeExact(room['bounds']) ||
        old['role'] != room['role'] ||
        old['lock_position'] != room['lock_position'] ||
        old['lock_size'] != room['lock_size'];
    return _editRecord({
      'type': 'upsert_room',
      'room': room,
    }, geometry: geometry);
  }

  Future<bool> removeRoom(String id) =>
      _editRecord({'type': 'remove_room', 'id': id}, geometry: true);
  Future<bool> unlockRoom(String id) async {
    final matches = (source['rooms'] as List? ?? []).where(
      (r) => r['id'] == id,
    );
    if (matches.isEmpty) return false;
    final room = Map<String, dynamic>.from(matches.first as Map);
    room['lock_position'] = false;
    room['lock_size'] = false;
    return saveRoom(room);
  }

  Future<void> optimize() async {
    if (!canOptimize) {
      note(
        activePackCount > exactPackLimit
            ? 'Exact optimization supports at most $exactPackLimit active packs; deactivate entries first.'
            : 'Generate a current dungeon before optimizing.',
      );
      return;
    }
    final stamp = revision;
    activeRevision = stamp;
    playback.pause();
    state = RunState.running;
    stage = 'Optimizing encounters';
    note('Optimizing encounters using the existing geometry…');
    try {
      final next = await engine.run(
        canonical,
        operation: EngineOperation.reallocate,
        maxEvents: 4096,
        detailedTrace: activePackCount <= 6 && rooms.length <= 8,
      );
      if (disposed) return;
      if (revision != stamp) {
        state = RunState.stale;
        note('Input changed; optimization was not applied.');
      } else if (state == RunState.cancelling ||
          next.document['outcome'] == 'cancelled') {
        state = stale ? RunState.stale : RunState.idle;
        analysisOutcome = 'cancelled · no optimality claim';
        note('Cancelled. The last valid result was kept.');
      } else if (next.succeeded) {
        final analysisStamp = revision;
        await _captureAnalysis(next, analysisStamp);
        if (disposed) return;
        if (revision != analysisStamp || state == RunState.cancelling) {
          state = stale ? RunState.stale : RunState.idle;
          note(
            'Input changed or cancelled while preparing analysis. Previous result retained.',
          );
          return;
        }
        result = next;
        resultRevision = revision;
        resultGeometryRevision = geometryRevision;
        state = RunState.successful;
        note('Completed. Geometry reused; exact allocation verified.');
      } else {
        await _captureAnalysis(next, stamp);
        state = RunState.failed;
        note('Optimization failed: ${_problem(next)}');
      }
    } catch (e) {
      if (!disposed) {
        state = RunState.failed;
        note('Optimization failed: $e');
      }
    } finally {
      activeRevision = -1;
      stage = '';
      _notify();
    }
  }

  Future<void> setRoomFixed(bool fixed) async {
    if (!canRun || (fixed && stale) || selectedRoom == null) return;
    final matches = rooms.where((r) => r['id'] == selectedRoom);
    if (matches.isEmpty) return;
    final stamp = revision;
    setCanvasDraft(true);
    try {
      final checked = await previewCanvas({
        'type': 'fix_room',
        'fixed': fixed,
        'room': matches.first,
      });
      if (commitCanvas(checked, stamp)) {
        note(
          fixed
              ? 'Room fixed at its current position and size. Generate again to arrange the other rooms around it.'
              : 'Room released. It can be regenerated next time.',
        );
      } else {
        note('Room change rejected: ${_problem(checked)}');
      }
    } catch (e) {
      note('Room change failed: $e');
    } finally {
      setCanvasDraft(false);
    }
  }

  void setCanvasDraft(bool value) {
    canvasDraft = value;
    _notify();
  }

  Future<EngineResult> previewCanvas(Map<String, dynamic> command) => _request(
    encodeExact({'project_json': canonical, 'command': command}),
    EngineOperation.edit,
  );
  Future<EngineResult> validateCanvasSource(String raw) => _normalize(raw);
  bool commitCanvas(EngineResult checked, int stamp, {bool geometry = true}) {
    if (!checked.succeeded || stamp != revision || disposed) return false;
    final text = checked.document['project_json'] as String;
    editorAnalysis =
        checked.document['editor_analysis'] as Map<String, dynamic>? ?? {};
    if (text != canonical) {
      document = decodeExact(text) as Map<String, dynamic>;
      canonical = text;
      revision++;
      if (geometry) geometryRevision++;
      allocationRevision++;
      validatedRevision = revision;
      if (!busy) state = result == null ? RunState.idle : RunState.stale;
    }
    note(
      'Project updated. ${result == null
          ? 'Ready to generate.'
          : geometryCurrent
          ? 'Geometry current; Optimize to refresh allocation.'
          : 'Geometry stale; Generate to refresh.'}',
    );
    return true;
  }

  Future<void> cancel() async {
    if (!busy) return;
    state = RunState.cancelling;
    note('Cancelling… The last valid result will be kept.');
    try {
      await engine.cancel();
    } catch (e) {
      note('Cancellation request failed: $e');
    }
  }

  void markSaved(String text, String name) {
    saved = text;
    filename = name;
    note(
      canonical == text
          ? 'Saved $name.'
          : 'Saved earlier revision. New edits remain unsaved.',
    );
  }

  @override
  void dispose() {
    scenario.removeListener(_scenarioChanged);
    scenario.dispose();
    play.dispose();
    playback.dispose();
    benchmarks.dispose();
    disposed = true;
    _timer?.cancel();
    unawaited(engine.close());
    unawaited(validator.close());
    super.dispose();
  }
}
