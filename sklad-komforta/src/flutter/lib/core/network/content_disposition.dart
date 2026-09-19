/// Извлекает имя скачиваемого файла из HTTP-заголовка Content-Disposition.
///
/// Сначала учитывается стандартное UTF-8 поле `filename*`, необходимое для
/// русских имён, затем обычное `filename` для совместимости со старыми API.
String? contentDispositionFileName(String? disposition) {
  if (disposition == null) return null;
  final encoded = RegExp(
    r"filename\*=UTF-8''([^;]+)",
    caseSensitive: false,
  ).firstMatch(disposition)?.group(1);
  if (encoded != null) return Uri.decodeComponent(encoded);
  return RegExp(
    r'filename="?([^";]+)',
    caseSensitive: false,
  ).firstMatch(disposition)?.group(1);
}
