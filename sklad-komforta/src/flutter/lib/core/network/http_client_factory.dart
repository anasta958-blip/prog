import 'package:http/http.dart' as http;

/// Создаёт платформенный HTTP-клиент; Web-реализация включает cookies.
http.Client createPlatformHttpClient() => http.Client();
