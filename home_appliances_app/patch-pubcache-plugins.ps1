# patch-pubcache-plugins.ps1
# Patches pub-cache copies of tflite and tflite_flutter to work with newer Gradle/SDKs.
# Run with: powershell -ExecutionPolicy Bypass -File .\patch-pubcache-plugins.ps1

$pubCache = Join-Path $env:LOCALAPPDATA 'Pub\Cache\hosted\pub.dev'
if (-not (Test-Path $pubCache)) {
  Write-Error "Pub cache path not found: $pubCache"
  exit 1
}

# Helper: backup file
function Backup-File($path) {
  $bak = "$path.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
  Copy-Item $path $bak -Force
  Write-Host "Backup created: $bak"
}

# Patch tflite plugin build.gradle: replace compile -> implementation
Get-ChildItem -Path $pubCache -Filter 'tflite-*' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $pkgDir = $_.FullName
  $buildGradle = Join-Path $pkgDir 'android\build.gradle'
  if (Test-Path $buildGradle) {
    Backup-File $buildGradle
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $content = Get-Content $buildGradle -Raw
    # Fix 1: replace compile with implementation
    $content = $content -replace '\bcompile\b', 'implementation'
    # Fix 2: Add namespace if missing
    if ($content -notmatch "namespace\s+") {
      $content = $content -replace 'android\s*\{', "android {`r`n    namespace 'sq.flutter.tflite'"
    }
    # Fix 3: Bump compileSdkVersion
    $content = $content -replace 'compileSdkVersion \d+', 'compileSdkVersion 34'
    
    [System.IO.File]::WriteAllText($buildGradle, $content, $utf8NoBom)
    Write-Host "Patched build.gradle for: $($_.Name)"
  }
  else {
    Write-Host "No build.gradle found for: $($_.Name)"
  }
}

# Patch tflite_flutter tensor.dart: add import dart:typed_data and replace UnmodifiableUint8ListView
Get-ChildItem -Path $pubCache -Filter 'tflite_flutter-*' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $pkgDir = $_.FullName
  $tensorFile = Join-Path $pkgDir 'lib\src\tensor.dart'
  if (Test-Path $tensorFile) {
    Backup-File $tensorFile
    $content = Get-Content $tensorFile -Raw
    if ($content -notmatch "import\s+'dart:typed_data';") {
      $content = $content -replace "(import\s+'dart:async';)", "`$1`r`nimport 'dart:typed_data';"
      Write-Host "Inserted dart:typed_data import into $tensorFile"
    }
    if ($content -match 'UnmodifiableUint8ListView\(') {
      $content = $content -replace 'UnmodifiableUint8ListView\(', 'Uint8List.fromList('
      Write-Host "Replaced UnmodifiableUint8ListView with Uint8List.fromList in $tensorFile"
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($tensorFile, $content, $utf8NoBom)
    Write-Host "Patched tensor.dart for: $($_.Name)"
  }
  else {
    Write-Host "No tensor.dart found for: $($_.Name)"
  }
}

Write-Host "Patch script finished. Now run: flutter clean ; flutter pub get ; flutter run"