import 'package:bcrypt/bcrypt.dart';

/// Hash a password using bcrypt with cost factor 12.
String hashPassword(String password) {
  return BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 12));
}

/// Verify a password against a bcrypt hash.
bool verifyPassword(String password, String hash) {
  try {
    return BCrypt.checkpw(password, hash);
  } catch (_) {
    return false;
  }
}
