import 'project_controller.dart';

class CanvasSnapshot {
  CanvasSnapshot(this.columns, this.rows, this.mask);
  factory CanvasSnapshot.of(ProjectController c) => CanvasSnapshot(
    c.settings['columns'] as int,
    c.settings['rows'] as int,
    List<String>.from(c.source['allowed_mask'] as List),
  );
  final int columns, rows;
  final List<String> mask;
  int get bytes => columns * rows * 2 + mask.length * 64 + 128;
}

class CanvasHistory {
  CanvasHistory({this.limit = 8 * 1024 * 1024});
  final int limit;
  final List<CanvasSnapshot> undo = [], redo = [];
  int get bytes => [...undo, ...redo].fold(0, (sum, e) => sum + e.bytes);
  void trim() {
    while (bytes > limit && (undo.isNotEmpty || redo.isNotEmpty)) {
      if (undo.isNotEmpty) {
        undo.removeAt(0);
      } else {
        redo.removeAt(0);
      }
    }
  }

  void record(CanvasSnapshot old) {
    undo.add(old);
    redo.clear();
    trim();
  }
}
