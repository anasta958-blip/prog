import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Создаёт BrowserClient с credentials для защищённой refresh-cookie API.
http.Client createPlatformHttpClient() =>
    BrowserClient()..withCredentials = true;
