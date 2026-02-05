import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'password_crypto.dart';

/// User data from the API.
class UserData {
  final String id;
  final String email;
  final String? name;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  const UserData({
    required this.id,
    required this.email,
    this.name,
    required this.isActive,
    required this.createdAt,
    this.lastLoginAt,
  });

  factory UserData.fromJson(Map<String, dynamic> json) => UserData(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastLoginAt: json['lastLoginAt'] != null
            ? DateTime.parse(json['lastLoginAt'] as String)
            : null,
      );
}

/// API token data.
class TokenData {
  final String label;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;

  const TokenData({
    required this.label,
    required this.scopes,
    required this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
  });

  factory TokenData.fromJson(Map<String, dynamic> json) => TokenData(
        label: json['label'] as String,
        scopes: (json['scopes'] as List<dynamic>?)?.cast<String>() ?? [],
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastUsedAt: json['lastUsedAt'] != null
            ? DateTime.parse(json['lastUsedAt'] as String)
            : null,
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
      );

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

/// Auth API client for user authentication and token management.
class AuthApiClient {
  final String baseUrl;
  final http.Client _client;

  AuthApiClient({String? baseUrl})
      : baseUrl = baseUrl ?? _detectBaseUrl(),
        _client = http.Client();

  /// Detect API base URL based on current location.
  static String _detectBaseUrl() {
    final location = web.window.location;
    // Dev mode: web on 4921, API on 4920
    if (location.port == '4921') {
      return '${location.protocol}//${location.hostname}:4920';
    }
    // Production: same origin
    return '';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
      };

  /// Register a new user.
  Future<UserData> register({
    required String email,
    required String password,
    String? name,
  }) async {
    // Encrypt password with server's public key
    final encryptedPassword =
        await PasswordCrypto.encryptPassword(password, baseUrl);

    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': encryptedPassword,
        if (name != null) 'name': name,
      }),
    );

    if (response.statusCode != 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      throw AuthApiException(
        statusCode: response.statusCode,
        code: error?['code'] as String? ?? 'unknown',
        message: error?['message'] as String? ?? 'Registration failed',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return UserData.fromJson(json['user'] as Map<String, dynamic>);
  }

  /// Login with email and password.
  Future<UserData> login({
    required String email,
    required String password,
  }) async {
    // Encrypt password with server's public key
    final encryptedPassword =
        await PasswordCrypto.encryptPassword(password, baseUrl);

    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': encryptedPassword,
      }),
    );

    if (response.statusCode != 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      throw AuthApiException(
        statusCode: response.statusCode,
        code: error?['code'] as String? ?? 'unknown',
        message: error?['message'] as String? ?? 'Login failed',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return UserData.fromJson(json['user'] as Map<String, dynamic>);
  }

  /// Logout (invalidate session).
  Future<void> logout() async {
    await _client.post(
      Uri.parse('$baseUrl/api/auth/logout'),
      headers: _headers,
    );
  }

  /// Get current user info.
  Future<UserData?> getCurrentUser() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AuthApiException(
        statusCode: response.statusCode,
        code: 'unknown',
        message: 'Failed to get user info',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final userData = json['user'];
    if (userData == null) {
      return null;
    }
    return UserData.fromJson(userData as Map<String, dynamic>);
  }

  /// Update current user profile.
  Future<UserData> updateProfile({
    String? name,
    String? password,
    String? currentPassword,
  }) async {
    // Encrypt passwords with server's public key
    final encryptedPassword = password != null
        ? await PasswordCrypto.encryptPassword(password, baseUrl)
        : null;
    final encryptedCurrentPassword = currentPassword != null
        ? await PasswordCrypto.encryptPassword(currentPassword, baseUrl)
        : null;

    final response = await _client.put(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: _headers,
      body: jsonEncode({
        if (name != null) 'name': name,
        if (encryptedPassword != null) 'password': encryptedPassword,
        if (encryptedCurrentPassword != null)
          'currentPassword': encryptedCurrentPassword,
      }),
    );

    if (response.statusCode != 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      throw AuthApiException(
        statusCode: response.statusCode,
        code: error?['code'] as String? ?? 'unknown',
        message: error?['message'] as String? ?? 'Update failed',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return UserData.fromJson(json['user'] as Map<String, dynamic>);
  }

  /// List user's tokens.
  Future<List<TokenData>> listTokens() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/tokens'),
      headers: _headers,
    );

    if (response.statusCode == 401) {
      throw AuthApiException(
        statusCode: 401,
        code: 'unauthorized',
        message: 'Login required',
      );
    }

    if (response.statusCode != 200) {
      throw AuthApiException(
        statusCode: response.statusCode,
        code: 'unknown',
        message: 'Failed to list tokens',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tokens = json['tokens'] as List<dynamic>;
    return tokens
        .map((t) => TokenData.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  /// Create a new token.
  Future<String> createToken({
    required String label,
    List<String>? scopes,
    int? expiresInDays,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/tokens'),
      headers: _headers,
      body: jsonEncode({
        'label': label,
        'scopes': scopes ?? [],
        if (expiresInDays != null) 'expiresInDays': expiresInDays,
      }),
    );

    if (response.statusCode == 401) {
      throw AuthApiException(
        statusCode: 401,
        code: 'unauthorized',
        message: 'Login required',
      );
    }

    if (response.statusCode != 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      throw AuthApiException(
        statusCode: response.statusCode,
        code: error?['code'] as String? ?? 'unknown',
        message: error?['message'] as String? ?? 'Failed to create token',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['token'] as String;
  }

  /// Delete a token.
  Future<void> deleteToken(String label) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/tokens/$label'),
      headers: _headers,
    );

    if (response.statusCode == 401) {
      throw AuthApiException(
        statusCode: 401,
        code: 'unauthorized',
        message: 'Login required',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 404) {
      throw AuthApiException(
        statusCode: response.statusCode,
        code: 'unknown',
        message: 'Failed to delete token',
      );
    }
  }

  void dispose() {
    _client.close();
  }
}

class AuthApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  AuthApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'AuthApiException($statusCode, $code): $message';
}
