import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// AES-256-CBC encryption/decryption for locally cached PII.
///
/// Format of an encrypted value:
///   base64(IV) + ':' + base64(ciphertext)
///
/// The 32-byte key is read from the PROFILE_CACHE_KEY env variable.
/// A random 16-byte IV is generated for every encrypt call so that
/// two identical plaintexts never produce the same ciphertext.
class CryptoService {
  CryptoService._();

  static Key _buildKey() {
    final raw = dotenv.env['PROFILE_CACHE_KEY'] ?? '';
    final bytes = utf8.encode(raw);
    // Exactly 32 bytes for AES-256 (pad with 0 / truncate as needed)
    final keyBytes = Uint8List(32);
    for (var i = 0; i < 32 && i < bytes.length; i++) {
      keyBytes[i] = bytes[i];
    }
    return Key(keyBytes);
  }

  /// Encrypts [plainText] and returns a single storable string.
  static String encrypt(String plainText) {
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(_buildKey(), mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypts a value previously produced by [encrypt].
  /// Throws [FormatException] if the input is malformed.
  static String decrypt(String cipherText) {
    final parts = cipherText.split(':');
    if (parts.length != 2) {
      throw const FormatException('Invalid encrypted data format');
    }
    final iv = IV.fromBase64(parts[0]);
    final encrypter = Encrypter(AES(_buildKey(), mode: AESMode.cbc));
    return encrypter.decrypt64(parts[1], iv: iv);
  }
}
