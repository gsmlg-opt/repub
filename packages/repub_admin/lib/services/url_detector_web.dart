import 'dart:html' as html;
import 'url_detector.dart';

/// URL detector for web platform using dart:html.
class WebUrlDetector implements UrlDetector {
  @override
  String detectBaseUrl() {
    final location = html.window.location;
    // Dev mode: admin on different port, API on 4920
    if (location.port == '4922') {
      return '${location.protocol}//${location.hostname}:4920';
    }
    // Production: same origin
    return '';
  }
}

/// Factory function that returns the platform-appropriate URL detector.
UrlDetector createUrlDetector() => WebUrlDetector();
