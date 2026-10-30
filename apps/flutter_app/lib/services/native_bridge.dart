import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'package:path/path.dart' as p;

import 'package:ffi/ffi.dart';

/// Thin ABI boundary to the Rust core. The platform runner must bundle the
/// matching driveflow_core library. The app remains usable for UI preview if
/// the native library is not yet installed.
final class NativeBridge {
  NativeBridge._(this._library);

  final ffi.DynamicLibrary? _library;

  static NativeBridge load() {
    try {
      final executableDirectory = p.dirname(Platform.resolvedExecutable);
      final library = Platform.isWindows
          ? ffi.DynamicLibrary.open(p.join(executableDirectory, 'driveflow_core.dll'))
          : Platform.isMacOS
              ? ffi.DynamicLibrary.open(p.join(executableDirectory, '..', 'Frameworks', 'libdriveflow_core.dylib'))
              : Platform.isAndroid
                  ? ffi.DynamicLibrary.open('libdriveflow_core.so')
                  : throw UnsupportedError('DriveFlow native core is not available on this platform.');
      return NativeBridge._(library);
    } on Object {
      return NativeBridge._(null);
    }
  }

  bool get isAvailable => _library != null;

  String get version {
    final library = _library;
    if (library == null) return 'unavailable';
    final readVersion = library.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('driveflow_version');
    final pointer = readVersion();
    try {
      return pointer.toDartString();
    } finally {
      library.lookupFunction<ffi.Void Function(ffi.Pointer<Utf8>), void Function(ffi.Pointer<Utf8>)>('driveflow_string_free')(pointer);
    }
  }

  String getTelegramStatus() {
    return _call0('driveflow_telegram_status');
  }

  String startTelegram({required int apiId, required String apiHash, required String databaseDirectory, required String encryptionKey}) {
    final library = _library;
    if (library == null) return '{"ok":false,"error":"native_core_unavailable"}';
    final hash = apiHash.toNativeUtf8();
    final directory = databaseDirectory.toNativeUtf8();
    final key = encryptionKey.toNativeUtf8();
    try {
      final call = library.lookupFunction<ffi.Pointer<Utf8> Function(ffi.Int32, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>), ffi.Pointer<Utf8> Function(int, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>)>('driveflow_telegram_start');
      return _take(call(apiId, hash, directory, key));
    } finally { calloc.free(hash); calloc.free(directory); calloc.free(key); }
  }

  String submitPhone(String phone) => _callString('driveflow_telegram_phone', phone);
  String submitCode(String code) => _callString('driveflow_telegram_code', code);
  String submitPassword(String password) => _callString('driveflow_telegram_password', password);
  String getTelegramChats() => _call0('driveflow_telegram_chats');

  String getTelegramHistory(int chatId, {int limit = 60}) {
    final library = _library;
    if (library == null) return '{"ok":false,"error":"native_core_unavailable"}';
    final call = library.lookupFunction<ffi.Pointer<Utf8> Function(ffi.Int64, ffi.Int32), ffi.Pointer<Utf8> Function(int, int)>('driveflow_telegram_history');
    return _take(call(chatId, limit));
  }

  String downloadTelegramFile(int fileId) {
    final library = _library;
    if (library == null) return '{"ok":false,"error":"native_core_unavailable"}';
    final call = library.lookupFunction<ffi.Pointer<Utf8> Function(ffi.Int32), ffi.Pointer<Utf8> Function(int)>('driveflow_telegram_download_file');
    return _take(call(fileId));
  }

  String sendFile(int chatId, String path, {String caption = ''}) {
    final library = _library;
    if (library == null) return '{"ok":false,"error":"native_core_unavailable"}';
    final nativePath = path.toNativeUtf8();
    final nativeCaption = caption.toNativeUtf8();
    try {
      final call = library.lookupFunction<ffi.Pointer<Utf8> Function(ffi.Int64, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>), ffi.Pointer<Utf8> Function(int, ffi.Pointer<Utf8>, ffi.Pointer<Utf8>)>('driveflow_telegram_send_file');
      return _take(call(chatId, nativePath, nativeCaption));
    } finally { calloc.free(nativePath); calloc.free(nativeCaption); }
  }

  String _call0(String symbol) {
    final library = _library;
    if (library == null) return '{"ok":false,"error":"native_core_unavailable"}';
    final call = library.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>(symbol);
    return _take(call());
  }

  String _callString(String symbol, String value) {
    final library = _library;
    if (library == null) return '{"ok":false,"error":"native_core_unavailable"}';
    final input = value.toNativeUtf8();
    try {
      final call = library.lookupFunction<ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>), ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8>)>(symbol);
      return _take(call(input));
    } finally { calloc.free(input); }
  }

  String _take(ffi.Pointer<Utf8> pointer) {
    try { return pointer.toDartString(); }
    finally { _library!.lookupFunction<ffi.Void Function(ffi.Pointer<Utf8>), void Function(ffi.Pointer<Utf8>)>('driveflow_string_free')(pointer); }
  }
}
