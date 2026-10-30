# DriveFlow

DriveFlow is a native Flutter application with a Rust core for organizing files and transferring them directly to the user's own Telegram account. It has no ads, subscriptions, or relay server. Desktop builds use Flutter's native Windows/macOS runners; Android uses a native APK. There is no browser shell or WebView.

> Starter scaffold: the UI and local Rust queue are implemented as a foundation. Telegram network operations require a locally built TDLib and Telegram `api_id`/`api_hash` supplied by the developer. Never commit those credentials or a user's session database.

## Layout

```text
apps/flutter_app/     Flutter UI and Dart FFI service boundary
core/rust/            Rust core (C ABI, queue, local metadata)
packaging/windows/    Inno Setup installer definition
packaging/macos/      DMG packaging script
packaging/android/    Android release notes/configuration
.github/workflows/    Tag-triggered multi-platform release workflow
scripts/              Local release helpers
```

## Requirements

- Flutter stable with Windows, macOS, and Android targets enabled
- Rust stable, plus each platform's native toolchain
- TDLib built for each target architecture and placed beside the app/native library search path
- Telegram API credentials from [my.telegram.org](https://my.telegram.org)
- Inno Setup 6 for Windows installer creation

The Flutter view can be explored without Telegram credentials. The Rust crate compiles independently and exports a small C ABI. TDLib is intentionally a native dependency rather than a Rust reimplementation: the bridge expects the official TDLib JSON C interface (`td_json_client_create`, `td_json_client_send`, `td_json_client_receive`, `td_json_client_destroy`). See [TDLib getting started](https://core.telegram.org/tdlib/getting-started) and [Flutter native FFI](https://docs.flutter.dev/platform-integration/bind-native-code).

## Initialize platform runners

This repository contains the requested application sources. On a machine with Flutter installed, from `apps/flutter_app` run:

```powershell
flutter create --project-name driveflow --platforms=windows,macos,android .
flutter pub get
```

Flutter may create runner scaffolding alongside these Dart files. Keep the generated native runner and its signing configuration in source control. For Windows, enable Developer Mode or use an elevated shell if Flutter requires symlink permission on first dependency setup.

Build the Rust core for the host:

```powershell
cd ../../core/rust
cargo build --release
```

The desktop Rust library names are `driveflow_core.dll` (Windows), `libdriveflow_core.dylib` (macOS), and `libdriveflow_core.so` (Android/Linux). Copy the appropriate library into the Flutter runner's native library location before using the FFI service. Android needs one `.so` per supported ABI (arm64-v8a, armeabi-v7a, x86_64); macOS universal builds need both arm64 and x86_64 slices or separate release artifacts.

## Telegram / TDLib integration

TDLib owns authorization state and encrypted database storage. The app must call `setTdlibParameters` after `authorizationStateWaitTdlibParameters`, then respond to authorization state updates, including phone number, code, and optional password. Chat discovery and sending use official TDLib requests; the starter bridge models these operations and returns an explicit unavailable error until a compatible TDLib library is loaded. Do not send credentials to a service: all account traffic is direct between TDLib and Telegram.

Provide `api_id` and `api_hash` through a secure build-time configuration mechanism. Treat the TDLib database encryption key and session directory as secrets. Use OS secure storage for the database key; do not store it in preferences or logs. TDLib session databases can contain sensitive account data.

## Releases

Push a version tag such as `v1.0.0`. `.github/workflows/release.yml` builds a Windows x64 installer, Android release APK, and macOS DMG, then attaches them to a GitHub Release. GitHub repository secrets expected by release builds:

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`
- `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (optional; omit to build an unsigned APK)
- `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY` (optional; unsigned DMG if omitted)

Unsigned builds are suitable for internal distribution only; Windows SmartScreen and macOS Gatekeeper may show trust warnings. Store release-signing secrets in GitHub Actions secrets, never in the repository. Review Telegram's API terms and distribution requirements before publishing.

Artifact names:

- `DriveFlow-Setup-v1.0.0-x64.exe`
- `DriveFlow-Android-v1.0.0-release.apk`
- `DriveFlow-macOS-v1.0.0.dmg`

## Current scope

The starter includes the dark dashboard, login/code UI, chat picker contract, Rust queue/storage primitives, TDLib JSON request builders, and release packaging skeleton. The Dart FFI currently exposes only core version/status; `TelegramService` methods intentionally stop with explicit unimplemented errors until the TDLib session lifecycle and update stream are wired through that ABI. The file chooser/drop surface and dashboard data are UI scaffolding, not working transfers. Full TDLib native builds, secure key storage adapter, recursive filesystem indexing, upload pause/resume wired to TDLib updates, signing identities, and store notarization must be configured before a release is production-ready. No fake Telegram data or relay backend is included.
