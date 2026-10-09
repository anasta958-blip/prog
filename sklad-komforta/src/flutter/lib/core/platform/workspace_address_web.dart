import 'dart:js_interop';

@JS('window.location.href')
external String get _href;
@JS('window.history.replaceState')
external void _replaceState(JSAny? data, String title, String url);

/// Восстанавливает раздел из фрагмента адреса; query-параметры не изменяются.
String readWorkspacePath() => Uri.parse(_href).fragment;

/// Обновляет только фрагмент, сохраняя клиентский quoteAccessToken в query.
void writeWorkspacePath(String path) => _replaceState(
  null,
  '',
  Uri.parse(_href).replace(fragment: path).toString(),
);
