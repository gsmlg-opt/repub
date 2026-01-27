import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:repub_model/repub_model.dart';

import 'url_detector_stub.dart'
    if (dart.library.html) 'url_detector_web.dart';

// Events
abstract class AuthEvent {}

class AuthCheckRequested extends AuthEvent {}

class AuthLoginRequested extends AuthEvent {
  final String username;
  final String password;

  AuthLoginRequested({required this.username, required this.password});
}

class AuthLogoutRequested extends AuthEvent {}

// States
abstract class AuthState {
  final AdminUser? user;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
  });

  bool get isAuthenticated => user != null;
}

class AuthInitial extends AuthState {
  const AuthInitial() : super(isLoading: true);
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(AdminUser user) : super(user: user);
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({super.error});
}

class AuthLoading extends AuthState {
  const AuthLoading({super.user}) : super(isLoading: true);
}

class AuthError extends AuthState {
  const AuthError(String error) : super(error: error);
}

// Bloc
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final String baseUrl;
  final http.Client _client;

  AuthBloc({String? baseUrl})
      : baseUrl = baseUrl ?? _detectBaseUrl(),
        _client = http.Client(),
        super(const AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthLoginRequested>(_onAuthLoginRequested);
    on<AuthLogoutRequested>(_onAuthLogoutRequested);

    // Check auth on initialization
    add(AuthCheckRequested());
  }

  static String _detectBaseUrl() {
    return createUrlDetector().detectBaseUrl();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
      };

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/admin/api/auth/me'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final user =
            AdminUser.fromJson(json['adminUser'] as Map<String, dynamic>);
        emit(AuthAuthenticated(user));
      } else {
        emit(const AuthUnauthenticated());
      }
    } catch (e) {
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onAuthLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading(user: state.user));

    try {
      final response = await _client.post(
        Uri.parse('$baseUrl/admin/api/auth/login'),
        headers: _headers,
        body: jsonEncode({
          'username': event.username,
          'password': event.password,
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final user =
            AdminUser.fromJson(json['adminUser'] as Map<String, dynamic>);
        emit(AuthAuthenticated(user));
      } else {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final error = json['error'] as Map<String, dynamic>;
        final message = error['message'] as String? ?? 'Login failed';
        emit(AuthError(message));
        emit(const AuthUnauthenticated());
      }
    } catch (e) {
      final message = e.toString();
      emit(AuthError(message));
      emit(const AuthUnauthenticated());
    }
  }

  Future<void> _onAuthLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _client.post(
        Uri.parse('$baseUrl/admin/api/auth/logout'),
        headers: _headers,
      );
    } catch (e) {
      // Ignore logout errors
    }

    emit(const AuthUnauthenticated());
  }

  @override
  Future<void> close() {
    _client.close();
    return super.close();
  }
}
