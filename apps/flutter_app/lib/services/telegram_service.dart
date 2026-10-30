import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'native_bridge.dart';

enum TelegramAuthStep { needsConfiguration, starting, waitingForPhone, waitingForCode, waitingForPassword, ready, closed, error }

class TelegramChat {
  const TelegramChat({required this.id, required this.title, this.isSelf = false});
  final int id;
  final String title;
  final bool isSelf;
}

/// Flutter facade over the Rust/TDLib FFI. The Rust core owns the Telegram
/// client and processes TDLib updates in order whenever status is polled.
class TelegramService {
  TelegramService(this._native);
  final NativeBridge _native;
  static const apiId = String.fromEnvironment('TELEGRAM_API_ID');
  static const apiHash = String.fromEnvironment('TELEGRAM_API_HASH');
  static const _secureStorage = FlutterSecureStorage();
  static const _keyName = 'driveflow.tdlib.database_key';

  TelegramAuthStep get authStep {
    final response = _read(_native.getTelegramStatus());
    if (response['ok'] != true) return response['error'] == 'tdlib_not_initialized'
        ? (apiId.isEmpty || apiHash.isEmpty ? TelegramAuthStep.needsConfiguration : TelegramAuthStep.starting)
        : TelegramAuthStep.error;
    return switch (response['authorization_state']) {
      'authorizationStateWaitTdlibParameters' => TelegramAuthStep.starting,
      'authorizationStateWaitPhoneNumber' => TelegramAuthStep.waitingForPhone,
      'authorizationStateWaitCode' => TelegramAuthStep.waitingForCode,
      'authorizationStateWaitPassword' => TelegramAuthStep.waitingForPassword,
      'authorizationStateReady' => TelegramAuthStep.ready,
      'authorizationStateClosed' => TelegramAuthStep.closed,
      _ => TelegramAuthStep.error,
    };
  }

  String? get lastError => _read(_native.getTelegramStatus())['error'] as String?;

  Future<void> initialize() async {
    _requireConfigured();
    final directory = await getApplicationSupportDirectory();
    final dbPath = '${directory.path}${directory.path.endsWith('/') || directory.path.endsWith('\\') ? '' : '/'}telegram';
    final key = await _getOrCreateEncryptionKey();
    _expectOk(_native.startTelegram(apiId: int.parse(apiId), apiHash: apiHash, databaseDirectory: dbPath, encryptionKey: key));
    // First poll consumes TDLib's initial authorization state and sends parameters.
    _native.getTelegramStatus();
  }

  Future<void> submitPhoneNumber(String phone) async {
    _requireConfigured();
    _expectOk(_native.submitPhone(phone));
  }

  Future<void> submitCode(String code) async => _expectOk(_native.submitCode(code));
  Future<void> submitPassword(String password) async => _expectOk(_native.submitPassword(password));

  Future<List<TelegramChat>> fetchPersonalChats() async {
    _native.getTelegramStatus();
    final payload = _read(_native.getTelegramChats());
    if (payload['ok'] != true) throw StateError(_friendlyError(payload['error']));
    final chats = (payload['chats'] as List<dynamic>? ?? const []);
    return chats.map((item) {
      final chat = item as Map<String, dynamic>;
      return TelegramChat(id: int.parse(chat['id'].toString()), title: (chat['title'] as String?) ?? 'Personal chat');
    }).toList(growable: false);
  }

  Future<void> sendFile({required int chatId, required String path}) async => _expectOk(_native.sendFile(chatId, path));

  Future<String> _getOrCreateEncryptionKey() async {
    final existing = await _secureStorage.read(key: _keyName);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final generated = base64.encode(List<int>.generate(32, (_) => random.nextInt(256)));
    await _secureStorage.write(key: _keyName, value: generated);
    return generated;
  }

  void _requireConfigured() {
    if (!_native.isAvailable) throw StateError('The DriveFlow Rust core is not bundled with this app.');
    if (apiId.isEmpty || apiHash.isEmpty) throw StateError('Configure TELEGRAM_API_ID and TELEGRAM_API_HASH in the release build.');
    if (int.tryParse(apiId) == null) throw StateError('TELEGRAM_API_ID must be a number.');
  }

  void _expectOk(String raw) {
    final response = _read(raw);
    if (response['ok'] != true) throw StateError(_friendlyError(response['error']));
  }

  Map<String, dynamic> _read(String raw) => jsonDecode(raw) as Map<String, dynamic>;

  String _friendlyError(Object? error) => switch (error) {
        'native_core_unavailable' => 'The DriveFlow native core is not installed.',
        'tdlib_not_initialized' => 'Telegram is still starting. Please wait a moment and try again.',
        'telegram_not_started' => 'Start the Telegram connection first.',
        'invalid_telegram_configuration' => 'The Telegram API configuration is invalid.',
        null => 'The Telegram request failed.',
        _ => error.toString(),
      };
}
