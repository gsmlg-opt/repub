import 'dart:convert';
import 'dart:io';
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

  PasswordCrypto._internal(this.publicKey, this.privateKey) {
    _encrypter = Encrypter(RSA(
      publicKey: publicKey,
      privateKey: privateKey,
      encoding: RSAEncoding.OAEP,
      digest: RSADigest.SHA256,
    ));
  }

  /// Load existing RSA key pair or generate and save a new one.
  static Future<PasswordCrypto> loadOrGenerate(String keyPath) async {
    final file = File(keyPath);
    if (file.existsSync()) {
      try {
        final jsonStr = await file.readAsString();
        final json = jsonDecode(jsonStr);
        final n = BigInt.parse(json['n'], radix: 16);
        final e = BigInt.parse(json['e'], radix: 16);
        final d = BigInt.parse(json['d'], radix: 16);
        final p = BigInt.parse(json['p'], radix: 16);
        final q = BigInt.parse(json['q'], radix: 16);

        final pubKey = RSAPublicKey(n, e);
        final privKey = RSAPrivateKey(n, d, p, q);
        return PasswordCrypto._internal(pubKey, privKey);
      } catch (e) {
        // Fallback to generating new
      }
    }

    final crypto = PasswordCrypto();
    try {
      final json = {
        'n': crypto.publicKey.modulus!.toRadixString(16),
        'e': crypto.publicKey.exponent!.toRadixString(16),
        'd': crypto.privateKey.privateExponent!.toRadixString(16),
        'p': crypto.privateKey.p!.toRadixString(16),
        'q': crypto.privateKey.q!.toRadixString(16),
      };
      file.parent.createSync(recursive: true);
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      // Ignore write errors
    }
    return crypto;
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
