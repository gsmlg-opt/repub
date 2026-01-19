import 'package:repub_model/repub_model.dart';

/// Authentication result.
sealed class AuthResult {}

class AuthSuccess extends AuthResult {
  final AuthToken token;
  AuthSuccess(this.token);
}

class AuthMissing extends AuthResult {}

class AuthInvalid extends AuthResult {
  final String message;
  AuthInvalid(this.message);
}

class AuthForbidden extends AuthResult {
  final String message;
  AuthForbidden(this.message);
}
