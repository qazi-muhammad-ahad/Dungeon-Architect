enum EngineOperation {
  validate,
  generate,
  route,
  optimize,
  run,
  normalize,
  newProject,
  edit,
}

class EngineException implements Exception {
  const EngineException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

class EngineProgress {
  const EngineProgress(this.state, this.stage, this.outcome);
  final int state;
  final int stage;
  final int outcome;
  String get stageName => const [
    'Queued',
    'Validating',
    'Generating rooms',
    'Routing corridors',
    'Optimizing encounters',
    'Preparing result',
    'Finished',
  ][stage.clamp(0, 6)];
}

class EngineResult {
  const EngineResult(this.rawJson, this.document);
  // Always use rawJson for export: int64 values remain numeric JSON tokens.
  final String rawJson;
  // On web, integers beyond +/- (2^53-1) are exact decimal strings, never
  // silently rounded doubles. Use BigInt.parse for arithmetic on these fields.
  final Map<String, dynamic> document;
  bool get succeeded => document['outcome'] == 'success';
}
