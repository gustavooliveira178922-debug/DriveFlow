import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

/// Thin ABI boundary to the Rust core. The platform runner must bundle the
/// matching driveflow_core library. The app remains usable for UI preview if
/// the native library is not yet installed.
final class NativeBridge {
  NativeBridge._(this._library);

  final ffi.DynamicLibrary? _library;

  static NativeBridge load() {
    try {
      final library = Platform.isWindows
          ? ffi.DynamicLibrary.open('driveflow_core.dll')
          : Platform.isMacOS
              ? ffi.DynamicLibrary.open('libdriveflow_core.dylib')
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
    final library = _library;
    if (library == null) return '{"ok":false,"error":"native_core_unavailable"}';
    final status = library.lookupFunction<ffi.Pointer<Utf8> Function(), ffi.Pointer<Utf8> Function()>('driveflow_telegram_status');
    final pointer = status();
    try {
      return pointer.toDartString();
    } finally {
      library.lookupFunction<ffi.Void Function(ffi.Pointer<Utf8>), void Function(ffi.Pointer<Utf8>)>('driveflow_string_free')(pointer);
    }
  }
}
