import 'dart:convert';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/export.dart';
import 'package:http/http.dart' as http;

/// Password encryption using RSA-OAEP with the server's public key.
class PasswordCrypto {
  /// Cache the public key to avoid repeated fetches.
  static RSAPublicKey? _cachedPublicKey;
  static Encrypter? _cachedEncrypter;

  /// Fetch the server's public key from /api/public-key.
  static Future<RSAPublicKey> _fetchPublicKey(String baseUrl) async {
    if (_cachedPublicKey != null) {
      return _cachedPublicKey!;
    }

    final response = await http.get(
      Uri.parse('$baseUrl/api/public-key'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch public key: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final modulusHex = json['modulus'] as String;
    final exponentHex = json['exponent'] as String;

    // Parse hex strings to BigInt
    final modulus = BigInt.parse(modulusHex, radix: 16);
    final exponent = BigInt.parse(exponentHex, radix: 16);

    // Create RSA public key
    final publicKey = RSAPublicKey(modulus, exponent);

    _cachedPublicKey = publicKey;
    _cachedEncrypter = Encrypter(RSA(
      publicKey: publicKey,
      encoding: RSAEncoding.OAEP,
    ));

    return publicKey;
  }

  /// Encrypt a password with the server's public key.
  static Future<String> encryptPassword(String password, String baseUrl) async {
    await _fetchPublicKey(baseUrl);

    if (_cachedEncrypter == null) {
      throw Exception('Encrypter not initialized');
    }

    final encrypted = _cachedEncrypter!.encrypt(password);
    return encrypted.base64;
  }

  /// Clear the cached public key (for testing).
  static void clearCache() {
    _cachedPublicKey = null;
    _cachedEncrypter = null;
  }
}
