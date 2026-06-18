<#
.SYNOPSIS
    Downloads the Gradle wrapper jar and builds the Haver Android APK.
.PARAMETER Release
    Build release APK instead of debug (both signed with debug keystore for testing).
.EXAMPLE
    .\setup.ps1          # builds debug APK
    .\setup.ps1 -Release # builds release APK
#>
param([switch]$Release)

$ErrorActionPreference = "Stop"
$GRADLE_VERSION = "8.6"
$WRAPPER_JAR = "$PSScriptRoot\gradle\wrapper\gradle-wrapper.jar"

function Find-ExistingWrapperJar {
    # 1. Check existing cached Gradle installations
    $gradleHome = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { "$env:USERPROFILE\.gradle" }
    $jar = Get-ChildItem -Path "$gradleHome\wrapper\dists" -Filter "gradle-wrapper.jar" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($jar) { return $jar.FullName }

    # 2. Check Android Studio bundled Gradle
    $asPaths = @(
        "$env:LOCALAPPDATA\Programs\Android\Android Studio",
        "C:\Program Files\Android\Android Studio",
        "C:\Program Files (x86)\Android\Android Studio"
    )
    foreach ($p in $asPaths) {
        if (Test-Path $p) {
            $jar = Get-ChildItem -Path $p -Filter "gradle-wrapper.jar" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($jar) { return $jar.FullName }
        }
    }
    return $null
}

# Ensure wrapper directory exists
New-Item -ItemType Directory -Force -Path "$PSScriptRoot\gradle\wrapper" | Out-Null

if (-not (Test-Path $WRAPPER_JAR)) {
    Write-Host "gradle-wrapper.jar not found. Searching for existing installation..."
    $existing = Find-ExistingWrapperJar
    if ($existing) {
        Write-Host "Found: $existing"
        Copy-Item $existing $WRAPPER_JAR
    } else {
        Write-Host "Downloading Gradle $GRADLE_VERSION distribution (~120 MB)..."
        $distUrl = "https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip"
        $zipPath = "$env:TEMP\gradle-$GRADLE_VERSION-bin.zip"
        $extractPath = "$env:TEMP\gradle-$GRADLE_VERSION-extract"

        Invoke-WebRequest -Uri $distUrl -OutFile $zipPath -UseBasicParsing
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        $jarSource = Get-ChildItem -Path $extractPath -Filter "gradle-wrapper.jar" -Recurse | Select-Object -First 1
        if (-not $jarSource) { throw "gradle-wrapper.jar not found in distribution zip." }
        Copy-Item $jarSource.FullName $WRAPPER_JAR
        Write-Host "Installed gradle-wrapper.jar from distribution."

        Remove-Item $zipPath, $extractPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Build
Set-Location $PSScriptRoot
$task = if ($Release) { "assembleRelease" } else { "assembleDebug" }
Write-Host "`nBuilding $task ..."
& "$PSScriptRoot\gradlew.bat" $task

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nBuild FAILED. See errors above." -ForegroundColor Red
    exit 1
}

$outDir = if ($Release) { "app\build\outputs\apk\release" } else { "app\build\outputs\apk\debug" }
$apk = Get-ChildItem -Path "$PSScriptRoot\$outDir" -Filter "*.apk" | Select-Object -First 1
Write-Host "`n SUCCESS  APK ready:" -ForegroundColor Green
Write-Host "  $($apk.FullName)" -ForegroundColor Cyan
Write-Host "`nInstall with:  adb install -r `"$($apk.FullName)`""
