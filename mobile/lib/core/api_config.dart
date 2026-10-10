import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kReleaseMode;

/// Where the backend lives.
///
/// Priority: value saved in Settings > `--dart-define=API_BASE_URL=...` >
/// platform default. The Android emulator reaches the host machine through
/// 10.0.2.2; a physical phone needs the computer's LAN IP, e.g.
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000`.
///
/// A release build made without API_BASE_URL has no backend (empty URL) and
/// uses the catalogue bundled in the app, so it can be shared and used
/// anywhere without a server.
class ApiConfig {
  static const _fromDefine = String.fromEnvironment('API_BASE_URL');

  static String get defaultBaseUrl {
    if (_fromDefine.isNotEmpty) return normalize(_fromDefine);
    if (kReleaseMode) return '';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }

  /// True when a backend URL is configured.
  static bool hasBackend(String baseUrl) => baseUrl.trim().isNotEmpty;

  /// Trims whitespace and trailing slashes; adds http:// when missing.
  static String normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isNotEmpty && !u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    return u;
  }

  static bool isValid(String url) {
    final uri = Uri.tryParse(normalize(url));
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }
}
