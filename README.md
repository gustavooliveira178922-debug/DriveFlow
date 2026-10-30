# DriveFlow

DriveFlow is a native Flutter application with a Rust core for organizing files and transferring them directly to the user's own Telegram account. It has no ads, subscriptions, or relay server. Desktop builds use Flutter's native Windows/macOS runners; Android uses a native APK. There is no browser shell or WebView.

> Telegram sign-in, personal chat discovery, direct document sends, desktop drag-and-drop, local folder management, and split-file recovery are wired through Flutter/Rust FFI and TDLib. Release builds compile and bundle TDLib for Windows and macOS. Transfer progress controls, persisted queues, and store signing/notarization remain future work.

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
- TDLib JSON library built for each release target (the release workflow does this from official TDLib source)
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

TDLib owns authorization state and encrypted database storage. The Rust core responds to `authorizationStateWaitTdlibParameters`, handles phone number, login code and optional two-step password states, resolves the signed-in user's **Saved Messages** self-chat, and sends selected files directly with TDLib. Group chats and other people's private chats are filtered out. Recent documents can be downloaded directly through TDLib. The UI polls a serialized Rust snapshot of TDLib updates. The encrypted session key is stored through Flutter Secure Storage, and files go directly between the app and Telegram. There is no relay service.

Google sign-in is required as the DriveFlow app identity and runs in the system browser with OAuth and PKCE. It does not replace Telegram authentication or provide access to Telegram storage. DriveFlow requests the Google People API phone-number scope to prefill the Telegram phone field when Google returns a number; the field stays editable, and the user must still submit that number and Telegram's sign-in code. Create an OAuth client in Google Cloud Console (installed/desktop app, loopback redirects), enable the People API, add the phone-number scope to the consent screen, and either enter its client ID in the app when prompted or set the Actions secret `GOOGLE_OAUTH_CLIENT_ID` for release builds. Google may require OAuth app verification before this sensitive scope can be used broadly; personal testing can be limited to configured test users.

Provide `api_id` and `api_hash` through a secure build-time configuration mechanism. Treat the TDLib database encryption key and session directory as secrets. Use OS secure storage for the database key; do not store it in preferences or logs. TDLib session databases can contain sensitive account data.

## Releases

Push a version tag such as `v1.0.12`. `.github/workflows/release.yml` builds a Windows x64 installer and macOS DMG, then attaches them to a GitHub Release. Android is intentionally released separately. GitHub repository secrets expected by release builds:

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`
- `GOOGLE_OAUTH_CLIENT_ID` (optional; required to enable Google account linking)
- `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (optional; omit to build an unsigned APK)
- `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY` (optional; unsigned DMG if omitted)

Unsigned builds are suitable for internal distribution only; Windows SmartScreen and macOS Gatekeeper may show trust warnings. Store release-signing secrets in GitHub Actions secrets, never in the repository. Review Telegram's API terms and distribution requirements before publishing.

Artifact names:

- `DriveFlow-Setup-v1.0.12-x64.exe`
- `DriveFlow-macOS-v1.0.12.dmg`

## Current scope

The app supports account sign-in, personal-chat selection, file-picker and desktop drag-and-drop sends, local folders, recent Telegram document browsing, direct downloads, and large-file splitting. Selecting a DriveFlow manifest downloads its parts and rebuilds the original in one flow; SHA-256 is checked before saving. It does not yet provide a resumable upload queue, pause/cancel controls, or signing/notarization. GitHub Actions is the validation path for native builds because Flutter and Rust toolchains are not installed in this local workspace. No fake Telegram data or relay backend is included.
