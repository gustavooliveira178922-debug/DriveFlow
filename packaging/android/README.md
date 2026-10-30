# Android packaging

Release builds are produced by `.github/workflows/release.yml` for `arm64-v8a`, `armeabi-v7a`, and `x86_64`. Rust is compiled to Android shared libraries with `cargo-ndk`; Flutter packages them from `android/app/src/main/jniLibs/<abi>/`.

To run locally, create the native runner with `flutter create --platforms=android,windows,macos .`, build the Rust core for each desired ABI with `cargo ndk`, then run `flutter build apk --release`. Set up signing in `android/key.properties` for production distribution; never check that file or a keystore into source control.
