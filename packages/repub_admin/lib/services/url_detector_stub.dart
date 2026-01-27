import 'url_detector.dart';

/// Stub URL detector for non-web platforms (testing).
class StubUrlDetectorImpl implements UrlDetector {
  @override
  String detectBaseUrl() => '';
}

/// Factory function that returns the platform-appropriate URL detector.
UrlDetector createUrlDetector() => StubUrlDetectorImpl();
