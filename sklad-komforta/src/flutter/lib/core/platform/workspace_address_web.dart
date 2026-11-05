import 'dart:js_interop';
import 'workspace_address_state.dart';

@JS('window.location.href')
external String get _href;
@JS('window.history.replaceState')
external void _replaceState(JSAny? data, String title, String url);
@JS('window.sessionStorage.getItem')
external String? _getItem(String key);
@JS('window.sessionStorage.setItem')
external void _setItem(String key, String value);

final _state = WorkspaceAddressState(
  readUrl: () => _href,
  replaceUrl: (url) => _replaceState(null, '', url),
  readStored: () => _getItem('workspace.path.v1'),
  writeStored: (path) => _setItem('workspace.path.v1', path),
);

void initializeWorkspaceAddress() => _state.initialize();

/// Восстанавливает раздел из фрагмента адреса; query-параметры не изменяются.
String readWorkspacePath() => _state.read();

/// Обновляет только фрагмент, сохраняя клиентский quoteAccessToken в query.
void writeWorkspacePath(String path) => _state.write(path);
