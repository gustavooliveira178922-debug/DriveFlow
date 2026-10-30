import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
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

class TelegramRemoteFile {
  const TelegramRemoteFile({required this.id, required this.name, required this.size, required this.downloaded, required this.downloading, required this.localPath});
  final int id;
  final String name;
  final int size;
  final bool downloaded;
  final bool downloading;
  final String localPath;
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
      return TelegramChat(id: int.parse(chat['id'].toString()), title: (chat['title'] as String?) ?? 'Saved Messages', isSelf: chat['is_saved_messages'] == true);
    }).toList(growable: false);
  }

  Future<List<TelegramRemoteFile>> fetchChatFiles(int chatId) async {
    _native.getTelegramStatus();
    final response = _read(_native.getTelegramHistory(chatId, limit: 100));
    if (response['ok'] != true) throw StateError(_friendlyError(response['error']));
    final messages = response['messages'] as List<dynamic>? ?? const [];
    final files = <TelegramRemoteFile>[];
    for (final raw in messages) {
      final message = raw as Map<String, dynamic>;
      final content = message['content'] as Map<String, dynamic>?;
      if (content?['@type'] != 'messageDocument') continue;
      final document = content?['document'] as Map<String, dynamic>?;
      final file = document?['document'] as Map<String, dynamic>?;
      final local = file?['local'] as Map<String, dynamic>?;
      final id = int.tryParse(file?['id']?.toString() ?? '');
      if (id == null) continue;
      files.add(TelegramRemoteFile(
        id: id,
        name: (document?['file_name'] as String?) ?? 'Telegram file',
        size: int.tryParse(file?['size']?.toString() ?? '') ?? 0,
        downloaded: local?['is_downloading_completed'] == true,
        downloading: local?['is_downloading_active'] == true,
        localPath: (local?['path'] as String?) ?? '',
      ));
    }
    return files;
  }

  Future<void> downloadFile(int fileId) async => _expectOk(_native.downloadTelegramFile(fileId));

  // Stay below Telegram's standard per-file upload ceiling. Parts are copied
  // with streams (never buffered into RAM), then a small JSON manifest is sent
  // last so DriveFlow can reassemble the original in one operation.
  static const int _partLimit = 1900 * 1024 * 1024;

  Future<void> sendFile({required int chatId, required String path}) async {
    final source = File(path);
    final length = await source.length();
    if (length <= _partLimit) {
      _expectOk(_native.sendFile(chatId, path));
      return;
    }

    final partCount = (length + _partLimit - 1) ~/ _partLimit;
    final checksum = (await sha256.bind(source.openRead()).first).toString();
    final id = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final workDirectory = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}driveflow-parts${Platform.pathSeparator}$id');
    await workDirectory.create(recursive: true);
    final parts = <String>[];
    for (var index = 0; index < partCount; index++) {
      final start = index * _partLimit;
      final end = min(start + _partLimit, length);
      final partName = '${source.uri.pathSegments.last}.part-${(index + 1).toString().padLeft(4, '0')}-of-${partCount.toString().padLeft(4, '0')}.dflow';
      final part = File('${workDirectory.path}${Platform.pathSeparator}$partName');
      await source.openRead(start, end).pipe(part.openWrite());
      if (await part.length() != end - start) throw StateError('A DriveFlow part was not written completely.');
      parts.add(part.path);
      final caption = 'DriveFlow part $id ${index + 1}/$partCount';
      _expectOk(_native.sendFile(chatId, part.path, caption: caption));
    }

    final manifest = File('${workDirectory.path}${Platform.pathSeparator}${source.uri.pathSegments.last}.driveflow.json');
    await manifest.writeAsString(jsonEncode({
      'format': 'driveflow-parts-v1',
      'id': id,
      'name': source.uri.pathSegments.last,
      'size': length,
      'sha256': checksum,
      'parts': parts.map((path) => path.split(Platform.pathSeparator).last).toList(),
    }), flush: true);
    _expectOk(_native.sendFile(chatId, manifest.path, caption: 'DriveFlow recovery manifest $id'));
  }

  /// Rebuild a split file selected from disk using its manifest and part files.
  Future<String> joinParts({required String manifestPath, required List<String> selectedPartPaths, required String outputDirectory}) async {
    final manifest = jsonDecode(await File(manifestPath).readAsString()) as Map<String, dynamic>;
    if (manifest['format'] != 'driveflow-parts-v1') throw const FormatException('This is not a DriveFlow parts manifest.');
    final expected = (manifest['parts'] as List<dynamic>).cast<String>();
    final byName = {for (final path in selectedPartPaths) path.split(Platform.pathSeparator).last: path};
    if (expected.any((name) => !byName.containsKey(name))) throw StateError('Select every part listed in this manifest.');
    final destination = File('$outputDirectory${Platform.pathSeparator}${manifest['name']}');
    if (await destination.exists()) throw StateError('A file with that name already exists in the destination folder.');
    final output = destination.openWrite();
    try {
      for (final name in expected) {
        await output.addStream(File(byName[name]!).openRead());
      }
    } finally {
      await output.close();
    }
    if (await destination.length() != manifest['size']) {
      await destination.delete();
      throw StateError('The reconstructed file size does not match its manifest.');
    }
    final checksum = (await sha256.bind(destination.openRead()).first).toString();
    if (checksum != manifest['sha256']) {
      await destination.delete();
      throw StateError('The reconstructed file failed its integrity check.');
    }
    return destination.path;
  }

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
