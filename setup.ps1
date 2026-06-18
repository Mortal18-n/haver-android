<#
.SYNOPSIS
    One-command bootstrap: downloads JDK 17 + Gradle wrapper, then builds the APK.
.PARAMETER Release
    Build a release APK instead of debug (both signed with debug keystore).
.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -Release
#>
param([switch]$Release)
$ErrorActionPreference = "Stop"

$GRADLE_VERSION = "8.6"
$PROJECT_ROOT   = $PSScriptRoot
$WRAPPER_JAR    = "$PROJECT_ROOT\gradle\wrapper\gradle-wrapper.jar"
$WRAPPER_PROPS  = "$PROJECT_ROOT\gradle\wrapper\gradle-wrapper.properties"
$JDK_DIR        = "$PROJECT_ROOT\.jdk"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Get-JavaVersion([string]$javaExe) {
    try {
        $out = & $javaExe -version 2>&1 | Select-Object -First 1
        if ($out -match '"(\d+)[\._]') {
            $major = [int]$Matches[1]
            # Java 8 reports "1.8.x", so major=1 → return 8
            return if ($major -eq 1) { 8 } else { $major }
        }
    } catch {}
    return 0
}

function Find-Java17 {
    # 1. JAVA_HOME
    if ($env:JAVA_HOME) {
        $exe = "$env:JAVA_HOME\bin\java.exe"
        if ((Test-Path $exe) -and (Get-JavaVersion $exe) -ge 17) { return $env:JAVA_HOME }
    }
    # 2. Project-local JDK (previous setup run)
    $local = Get-ChildItem -Path $JDK_DIR -Filter "java.exe" -Recurse -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch '\\jre\\' } | Select-Object -First 1
    if ($local -and (Get-JavaVersion $local.FullName) -ge 17) {
        return $local.Directory.Parent.FullName
    }
    # 3. Android Studio bundled JBR
    foreach ($p in @(
        "C:\Program Files\Android\Android Studio\jbr",
        "C:\Program Files (x86)\Android\Android Studio\jbr"
    )) {
        $exe = "$p\bin\java.exe"
        if ((Test-Path $exe) -and (Get-JavaVersion $exe) -ge 17) { return $p }
    }
    return $null
}

function Download-JDK17 {
    Write-Host "Java 17+ not found. Downloading Amazon Corretto JDK 17 (~200 MB)..."
    $zipPath = "$env:TEMP\corretto-17-windows-x64.zip"
    Invoke-WebRequest `
        -Uri "https://corretto.aws/downloads/latest/amazon-corretto-17-x64-windows-jdk.zip" `
        -OutFile $zipPath -UseBasicParsing

    Write-Host "Extracting JDK to $JDK_DIR ..."
    if (Test-Path $JDK_DIR) { Remove-Item $JDK_DIR -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $JDK_DIR | Out-Null
    Expand-Archive -Path $zipPath -DestinationPath $JDK_DIR -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    $javaExe = Get-ChildItem -Path $JDK_DIR -Filter "java.exe" -Recurse |
               Where-Object { $_.FullName -notmatch '\\jre\\' } | Select-Object -First 1
    if (-not $javaExe) { throw "java.exe not found after JDK extraction." }

    $jdkRoot = $javaExe.Directory.Parent.FullName
    Write-Host "JDK installed: $jdkRoot (Java $(Get-JavaVersion $javaExe.FullName))"
    return $jdkRoot
}

function Ensure-WrapperJar([string]$JavaHome) {
    # Skip if already present and valid (>50 KB)
    if ((Test-Path $WRAPPER_JAR) -and (Get-Item $WRAPPER_JAR).Length -gt 50000) {
        Write-Host "gradle-wrapper.jar already present ($([math]::Round((Get-Item $WRAPPER_JAR).Length/1KB)) KB)."
        return
    }

    # Try cached wrapper from a previous Gradle download
    $gradleUserHome = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { "$env:USERPROFILE\.gradle" }
    $cached = Get-ChildItem -Path "$gradleUserHome\wrapper\dists" -Filter "gradle-wrapper.jar" `
                  -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cached -and $cached.Length -gt 50000) {
        Write-Host "Using cached wrapper jar: $($cached.FullName)"
        Copy-Item $cached.FullName $WRAPPER_JAR -Force
        return
    }

    # Download Gradle distribution and generate wrapper via a minimal dummy project.
    # We use a dummy project (no AGP) so 'gradle wrapper' succeeds with ANY Java version.
    $tmpZip     = "$env:TEMP\gradle-$GRADLE_VERSION-bin.zip"
    $tmpExtract = "$env:TEMP\gradle-$GRADLE_VERSION-extract"
    $tmpProject = "$env:TEMP\haver-wrapper-gen"

    if (-not (Test-Path $tmpZip)) {
        Write-Host "Downloading Gradle $GRADLE_VERSION distribution (~130 MB)..."
        Invoke-WebRequest `
            -Uri "https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip" `
            -OutFile $tmpZip -UseBasicParsing
    }

    Write-Host "Extracting Gradle distribution..."
    if (Test-Path $tmpExtract) { Remove-Item $tmpExtract -Recurse -Force }
    Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force

    $gradleBat = "$tmpExtract\gradle-$GRADLE_VERSION\bin\gradle.bat"
    if (-not (Test-Path $gradleBat)) {
        throw "gradle.bat not found at expected path: $gradleBat"
    }

    # Minimal project — no plugins at all — so resolution never fails
    if (Test-Path $tmpProject) { Remove-Item $tmpProject -Recurse -Force }
    New-Item -ItemType Directory -Force -Path "$tmpProject\gradle\wrapper" | Out-Null
    Set-Content "$tmpProject\settings.gradle" "rootProject.name = 'wrapper-gen'"

    Write-Host "Running 'gradle wrapper' in minimal project to generate gradle-wrapper.jar..."
    $savedJavaHome = $env:JAVA_HOME
    $env:JAVA_HOME = $JavaHome
    Push-Location $tmpProject
    try {
        & $gradleBat wrapper --gradle-version $GRADLE_VERSION --distribution-type bin 2>&1 |
            ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { throw "gradle wrapper task failed (exit code $LASTEXITCODE)" }
    } finally {
        Pop-Location
        $env:JAVA_HOME = $savedJavaHome
    }

    $generated = "$tmpProject\gradle\wrapper\gradle-wrapper.jar"
    if (-not (Test-Path $generated) -or (Get-Item $generated).Length -lt 50000) {
        throw "gradle-wrapper.jar was not generated (or is too small). Check the output above."
    }

    Copy-Item $generated $WRAPPER_JAR -Force
    Write-Host "gradle-wrapper.jar ready: $([math]::Round((Get-Item $WRAPPER_JAR).Length/1KB)) KB"

    Remove-Item $tmpZip, $tmpExtract, $tmpProject -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path (Split-Path $WRAPPER_JAR) | Out-Null

# 1. Java 17+
Write-Host "=== Step 1: Java 17+ ==="
$jdkRoot = Find-Java17
if (-not $jdkRoot) { $jdkRoot = Download-JDK17 }
Write-Host "JDK: $jdkRoot"
$env:JAVA_HOME = $jdkRoot

# 2. gradle-wrapper.jar
Write-Host "`n=== Step 2: Gradle Wrapper ==="
Ensure-WrapperJar -JavaHome $jdkRoot

# Write wrapper properties (restore in case they were overwritten by the dummy project run)
Set-Content $WRAPPER_PROPS -Encoding UTF8 -Value @"
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
"@

# Pin the JDK in gradle.properties so the daemon always uses it
$jdkEscaped = $jdkRoot -replace '\\', '/'
$propsContent = Get-Content "$PROJECT_ROOT\gradle.properties" -Raw
if ($propsContent -match 'org\.gradle\.java\.home') {
    $propsContent = $propsContent -replace 'org\.gradle\.java\.home=.*', "org.gradle.java.home=$jdkEscaped"
} else {
    $propsContent += "`norg.gradle.java.home=$jdkEscaped`n"
}
Set-Content "$PROJECT_ROOT\gradle.properties" $propsContent -Encoding UTF8

# 3. Build
Write-Host "`n=== Step 3: Build APK ==="
Set-Location $PROJECT_ROOT
$task = if ($Release) { "assembleRelease" } else { "assembleDebug" }
Write-Host "Running: gradlew.bat $task"
Write-Host "(First run downloads Gradle $GRADLE_VERSION and dependencies — may take a few minutes)`n"
& "$PROJECT_ROOT\gradlew.bat" $task

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nBuild FAILED. See errors above." -ForegroundColor Red
    exit 1
}

$outDir = if ($Release) { "app\build\outputs\apk\release" } else { "app\build\outputs\apk\debug" }
$apk = Get-ChildItem -Path "$PROJECT_ROOT\$outDir" -Filter "*.apk" | Select-Object -First 1
Write-Host ""
Write-Host "  BUILD SUCCESS" -ForegroundColor Green
Write-Host "  APK: $($apk.FullName)" -ForegroundColor Cyan
Write-Host "  Install: adb install -r `"$($apk.FullName)`""
