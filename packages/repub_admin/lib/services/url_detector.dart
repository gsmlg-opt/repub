/// URL detector abstraction for cross-platform support.
///
/// This allows the admin client to detect the base URL in browser environments
/// while still being testable in VM tests.
abstract class UrlDetector {
  String detectBaseUrl();
}

/// URL detector that returns an empty string (for testing).
class StubUrlDetector implements UrlDetector {
  @override
  String detectBaseUrl() => '';
}
