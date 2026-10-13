class ProjectFiles {
  Future<Map<String, dynamic>?> open() async =>
      throw UnsupportedError('Open this editor in Chrome.');
  Future<Map<String, dynamic>> save(
    String raw,
    String name,
    bool saveAs,
  ) async => throw UnsupportedError('Open this editor in Chrome.');
  void adopt() {}
  void reset() {}
  void setDirty(bool value) {}
  void dispose() {}
}
