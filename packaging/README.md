# Native packaging notes

- Windows installer: Flutter's Windows runner plus Inno Setup 6, configured in `windows/installer/driveflow.iss`.
- Android: Flutter release APK with Rust `.so` libraries under generated Android `jniLibs`; CI currently publishes the ARM64 split APK as the named universal release artifact.
- macOS: Flutter `.app` bundle with universal Rust core, wrapped as a DMG. Developer ID signing and notarization are environment-dependent and must be added before public distribution.

TDLib binaries are not vendored. To package the real Telegram bridge, build TDLib from the official source for every target and put its JSON shared library under `apps/flutter_app/native/tdlib/<platform>/<arch>/`. The CI workflow copies it when present; without it, sign-in must report that TDLib is unavailable.
