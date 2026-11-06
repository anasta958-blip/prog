/// Navigation metadata only; document contents and credentials are never stored.
class WorkspaceAddressState {
  WorkspaceAddressState({
    required this.readUrl,
    required this.replaceUrl,
    required this.readStored,
    required this.writeStored,
  });

  final String Function() readUrl;
  final void Function(String) replaceUrl;
  final String? Function() readStored;
  final void Function(String) writeStored;
  String? _path;

  static String? validPath(String? value) =>
      value != null &&
          RegExp(
            r'^/(kanban|catalog|devices|company(?:/[a-zA-Z]+)?|company/settings/(?:legal|configuration(?:/[0-9]+)?)|company/documents/(?:quote|order)(?:/[a-zA-Z0-9_-]+)?)$',
          ).hasMatch(value)
      ? value
      : null;

  void initialize() {
    if (_path != null) return;
    final uri = Uri.parse(readUrl());
    // Public customer links must not overwrite the authenticated workspace.
    if (uri.queryParameters.containsKey('quoteAccessToken')) {
      _path = '';
      return;
    }
    String? stored;
    try {
      stored = readStored();
    } catch (_) {
      /* Storage may be disabled. */
    }
    _path = validPath(uri.fragment) ?? validPath(stored) ?? '/kanban';
    _persist();
  }

  String read() {
    initialize();
    return _path!;
  }

  void write(String path) {
    if (validPath(path) == null) return;
    _path = path;
    _persist();
    final uri = Uri.parse(readUrl());
    replaceUrl(uri.replace(fragment: path).toString());
  }

  void _persist() {
    try {
      writeStored(_path!);
    } catch (_) {
      /* Navigation still works in memory. */
    }
  }
}
