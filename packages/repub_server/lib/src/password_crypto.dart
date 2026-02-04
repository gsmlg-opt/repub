import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/export.dart';

/// RSA key pair for password encryption
class PasswordCrypto {
  late final RSAPublicKey publicKey;
  late final RSAPrivateKey privateKey;
  late final Encrypter _encrypter;

  /// Initialize with a new RSA key pair (2048-bit)
  PasswordCrypto() {
    final keyPair = _generateKeyPair();
    publicKey = keyPair.publicKey;
    privateKey = keyPair.privateKey;
    _encrypter = Encrypter(RSA(
      publicKey: publicKey,
      privateKey: privateKey,
      encoding: RSAEncoding.OAEP,
      digest: RSADigest.SHA256,
    ));
  }

  /// Generate RSA key pair
  AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _generateKeyPair({
    int bitLength = 2048,
  }) {
    final secureRandom = FortunaRandom();
    final seed = Uint8List.fromList(
      List.generate(32, (i) => DateTime.now().millisecondsSinceEpoch & 0xFF),
    );
    secureRandom.seed(KeyParameter(seed));

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), bitLength, 64),
        secureRandom,
      ));

    final pair = keyGen.generateKeyPair();
    return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
      pair.publicKey as RSAPublicKey,
      pair.privateKey as RSAPrivateKey,
    );
  }

  /// Get public key modulus and exponent as JSON (for JavaScript clients)
  Map<String, String> getPublicKeyJson() {
    return {
      'modulus': publicKey.modulus!.toRadixString(16),
      'exponent': publicKey.exponent!.toRadixString(16),
    };
  }

  /// Decrypt password that was encrypted with the public key
  String decryptPassword(String encryptedBase64) {
    try {
      final encrypted = Encrypted.fromBase64(encryptedBase64);
      return _encrypter.decrypt(encrypted);
    } catch (e) {
      throw Exception('Failed to decrypt password: $e');
    }
  }

  /// Encrypt password (for testing)
  String encryptPassword(String password) {
    final encrypted = _encrypter.encrypt(password);
    return encrypted.base64;
  }
}
