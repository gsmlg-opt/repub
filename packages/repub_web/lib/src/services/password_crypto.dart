import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

/// Password encryption using RSA-OAEP with the server's public key.
class PasswordCrypto {
  static bool _initialized = false;

  /// Initialize the password crypto module.
  static void _ensureInitialized() {
    if (_initialized) return;

    // Inject the encryption JavaScript code
    final script = '''
(function() {
  if (window.__repub_password_crypto) return;

  let cachedPublicKey = null;

  async function getPublicKey(baseUrl) {
    if (cachedPublicKey) {
      return cachedPublicKey;
    }

    const response = await fetch(baseUrl + '/api/public-key');
    if (!response.ok) {
      throw new Error('Failed to fetch public key: ' + response.statusText);
    }

    const json = await response.json();
    const modulusHex = json.modulus;
    const exponentHex = json.exponent;

    function hexToBytes(hex) {
      const bytes = new Uint8Array(hex.length / 2);
      for (let i = 0; i < hex.length; i += 2) {
        bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
      }
      return bytes;
    }

    function base64UrlEncode(bytes) {
      const base64 = btoa(String.fromCharCode.apply(null, bytes));
      return base64.replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=/g, '');
    }

    const modulus = hexToBytes(modulusHex);
    const exponent = hexToBytes(exponentHex);

    const jwk = {
      kty: 'RSA',
      n: base64UrlEncode(modulus),
      e: base64UrlEncode(exponent),
      alg: 'RSA-OAEP',
      ext: true,
    };

    const key = await crypto.subtle.importKey(
      'jwk',
      jwk,
      { name: 'RSA-OAEP', hash: 'SHA-256' },
      false,
      ['encrypt']
    );

    cachedPublicKey = key;
    return key;
  }

  async function encryptPassword(password, baseUrl) {
    const publicKey = await getPublicKey(baseUrl);
    const encoder = new TextEncoder();
    const passwordBytes = encoder.encode(password);

    const encrypted = await crypto.subtle.encrypt(
      { name: 'RSA-OAEP' },
      publicKey,
      passwordBytes
    );

    const bytes = new Uint8Array(encrypted);
    const base64 = btoa(String.fromCharCode.apply(null, bytes));
    return base64;
  }

  function clearCache() {
    cachedPublicKey = null;
  }

  window.__repub_password_crypto = {
    encryptPassword: encryptPassword,
    clearCache: clearCache
  };
})();
''';

    // Execute the script in the global scope
    (web.window as JSObject).callMethod('eval'.toJS, script.toJS);
    _initialized = true;
  }

  /// Encrypt a password with the server's public key.
  static Future<String> encryptPassword(String password, String baseUrl) async {
    _ensureInitialized();

    final crypto = (web.window as JSObject)['__repub_password_crypto'] as JSObject;
    final encryptFn = crypto['encryptPassword'] as JSFunction;

    final promise = encryptFn.callAsFunction(
      crypto,
      password.toJS,
      baseUrl.toJS,
    ) as JSPromise;

    final result = await promise.toDart;
    return (result as JSString).toDart;
  }

  /// Clear the cached public key (for testing).
  static void clearCache() {
    if (!_initialized) return;

    final crypto = (web.window as JSObject)['__repub_password_crypto'];
    if (crypto != null) {
      final clearFn = (crypto as JSObject)['clearCache'] as JSFunction;
      clearFn.callAsFunction(crypto);
    }
  }
}
