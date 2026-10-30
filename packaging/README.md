# Native packaging notes

- Windows installer: Flutter's Windows runner plus Inno Setup 6, configured in `windows/installer/driveflow.iss`.
- Android: Flutter universal release APK with Rust and TDLib `.so` libraries under generated Android `jniLibs` for arm64-v8a, armeabi-v7a, and x86_64.
- macOS: Flutter `.app` bundle with universal Rust core, wrapped as a DMG. Developer ID signing and notarization are environment-dependent and must be added before public distribution.

The release workflow builds TDLib's JSON interface from the official `tdlib/td` source, then bundles the platform library with the app. Android libraries are added under `android/app/src/main/jniLibs/`, Windows `tdjson.dll` sits beside the executable, and macOS libraries are placed in the app's `Contents/Frameworks` folder. Do not commit user session databases or encryption keys.
