import 'dart:convert';

import 'native_bridge.dart';

enum TelegramAuthStep { needsConfiguration, waitingForPhone, waitingForCode, waitingForPassword, ready, closed, error }

class TelegramChat {
  const TelegramChat({required this.id, required this.title, this.isSelf = false});
  final int id;
  final String title;
  final bool isSelf;
}

/// Telegram service facade. TDLib remains the source of truth for all auth,
/// chat and upload state; UI must consume updates rather than inventing success.
class TelegramService {
  TelegramService(this._native);
  final NativeBridge _native;

  static const apiId = String.fromEnvironment('TELEGRAM_API_ID');
  static const apiHash = String.fromEnvironment('TELEGRAM_API_HASH');

  TelegramAuthStep get authStep {
    final response = jsonDecode(_native.getTelegramStatus()) as Map<String, dynamic>;
    if (response['ok'] != true) return TelegramAuthStep.needsConfiguration;
    return switch (response['authorization_state']) {
      'authorizationStateWaitPhoneNumber' => TelegramAuthStep.waitingForPhone,
      'authorizationStateWaitCode' => TelegramAuthStep.waitingForCode,
      'authorizationStateWaitPassword' => TelegramAuthStep.waitingForPassword,
      'authorizationStateReady' => TelegramAuthStep.ready,
      'authorizationStateClosed' => TelegramAuthStep.closed,
      _ => TelegramAuthStep.error,
    };
  }

  Future<void> submitPhoneNumber(String phone) async {
    _requireConfigured();
    throw UnimplementedError('Connect this action to TDLib setAuthenticationPhoneNumber.');
  }

  Future<void> submitCode(String code) async {
    _requireConfigured();
    throw UnimplementedError('Connect this action to TDLib checkAuthenticationCode.');
  }

  Future<List<TelegramChat>> fetchPersonalChats() async {
    _requireConfigured();
    throw UnimplementedError('Map TDLib chat-list updates into the app chat model.');
  }

  Future<void> sendFile({required int chatId, required String path}) async {
    _requireConfigured();
    throw UnimplementedError('Send with TDLib sendMessage and inputMessageDocument/inputFileLocal.');
  }

  void _requireConfigured() {
    if (!_native.isAvailable) throw StateError('The DriveFlow Rust core / TDLib native libraries are not bundled.');
    if (apiId.isEmpty || apiHash.isEmpty) throw StateError('Build with TELEGRAM_API_ID and TELEGRAM_API_HASH configured.');
    throw StateError('The TDLib session methods are implemented in the Rust bridge, but the Flutter FFI session adapter still needs wiring.');
  }
}
