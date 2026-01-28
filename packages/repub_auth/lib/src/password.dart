import 'package:bcrypt/bcrypt.dart';
import 'package:repub_model/repub_model.dart';

/// Hash a password using bcrypt with cost factor 12.
String hashPassword(String password) {
  return BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 12));
}

/// Verify a password against a bcrypt hash.
///
/// Returns false for invalid passwords or if the hash format is invalid.
/// Logs unexpected errors for debugging purposes.
bool verifyPassword(String password, String hash) {
  try {
    return BCrypt.checkpw(password, hash);
  } on FormatException catch (e) {
    // Invalid hash format - this is expected for malformed hashes
    Logger.warn(
      'Password verification failed due to invalid hash format',
      component: 'auth',
      metadata: {'error': e.message},
    );
    return false;
  } catch (e) {
    // Unexpected errors - log for debugging
    Logger.error(
      'Password verification failed with unexpected error',
      component: 'auth',
      error: e,
    );
    return false;
  }
}
