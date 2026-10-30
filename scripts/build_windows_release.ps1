param(
  [string]$Version = "1.0.0",
  [string]$FlutterRoot = "apps/flutter_app",
  [string]$CoreRoot = "core/rust"
)
$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { throw "Flutter is required on PATH." }
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) { throw "Rust cargo is required on PATH." }

$FlutterPath = Join-Path $RepoRoot $FlutterRoot
if (-not (Test-Path (Join-Path $FlutterPath "windows"))) {
  Push-Location $FlutterPath
  try { flutter create --project-name driveflow --platforms=windows,macos,android . } finally { Pop-Location }
}

Push-Location (Join-Path $RepoRoot $CoreRoot)
try { cargo build --release --target x86_64-pc-windows-msvc } finally { Pop-Location }

Push-Location $FlutterPath
try {
  flutter pub get
  flutter build windows --release
} finally { Pop-Location }

$OutputDir = Join-Path $FlutterPath "build/windows/x64/runner/Release"
$CoreDll = Join-Path $RepoRoot "$CoreRoot/target/x86_64-pc-windows-msvc/release/driveflow_core.dll"
Copy-Item -LiteralPath $CoreDll -Destination $OutputDir -Force
$Iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if (-not $Iscc) { throw "Inno Setup 6 (ISCC.exe) is required to create the installer." }
& $Iscc.Source "/DAppVersion=$Version" (Join-Path $RepoRoot "packaging/windows/installer/driveflow.iss")
