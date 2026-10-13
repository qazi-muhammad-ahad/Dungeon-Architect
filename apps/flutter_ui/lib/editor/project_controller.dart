import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/engine.dart';
import 'exact_json.dart';

enum EditorView { design, analyze, play }

enum RunState { idle, running, cancelling, successful, stale, invalid, failed }

class ProjectController extends ChangeNotifier {
  ProjectController({Engine? engine, Engine? validator})
    : engine = engine ?? Engine(),
      validator = validator ?? Engine();
  Engine engine, validator;
  int documentEpoch = 0;
  Map<String, dynamic>? document;
  String canonical = '', filename = 'untitled.dungeon.json';
  String? saved;
  int revision = 0,
      validatedRevision = -1,
      resultRevision = -1,
      activeRevision = -1;
  int geometryRevision = 0, allocationRevision = 0;
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
  Map<String, dynamic>? get payload =>
      result?.document['result'] as Map<String, dynamic>?;
  List<dynamic> get rooms =>
      payload?['layout']?['rooms'] as List<dynamic>? ?? [];
  void _notify() {
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
      resultRevision = -1;
      selectedRoom = null;
      fieldErrors.clear();
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
    settings[key] = value <= BigInt.from(9007199254740991)
        ? value.toInt()
        : value;
    if (!busy) state = result == null ? RunState.idle : RunState.stale;
    _validateDraft();
  }

  void rename(String name) {
    if (document == null || loading || canvasDraft || source['name'] == name) {
      return;
    }
    source['name'] = name;
    revision++;
    if (!busy) state = result == null ? RunState.idle : RunState.stale;
    _validateDraft();
  }

  void _validateDraft() {
    final stamp = revision, raw = encodeExact(document);
    validating = true;
    _notify();
    _normalize(raw)
        .then((checked) {
          if (disposed || revision != stamp) return;
          if (checked.succeeded) {
            canonical = checked.document['project_json'] as String;
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

  Future<void> run() async {
    if (!canRun) return;
    final stamp = revision;
    activeRevision = stamp;
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
        next = await engine.run(winningSource);
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
        result = next;
        resultRevision = revision;
        state = RunState.successful;
        if (!rooms.any((r) => r['id'] == selectedRoom)) selectedRoom = null;
        note(
          'Completed. Exact allocation verified. First valid solution after $searchAttempt candidate${searchAttempt == 1 ? '' : 's'}; seed ${settings['seed']}.',
        );
      } else {
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
  bool commitCanvas(EngineResult checked, int stamp) {
    if (!checked.succeeded || stamp != revision || disposed) return false;
    final text = checked.document['project_json'] as String;
    editorAnalysis =
        checked.document['editor_analysis'] as Map<String, dynamic>? ?? {};
    if (text != canonical) {
      document = decodeExact(text) as Map<String, dynamic>;
      canonical = text;
      revision++;
      geometryRevision++;
      allocationRevision++;
      validatedRevision = revision;
      if (!busy) state = result == null ? RunState.idle : RunState.stale;
    }
    note(
      'Canvas updated. ${result == null ? 'Ready to generate.' : 'Previous result is stale.'}',
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
    disposed = true;
    _timer?.cancel();
    unawaited(engine.close());
    unawaited(validator.close());
    super.dispose();
  }
}
