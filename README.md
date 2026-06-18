# Haver Android — Kiosk Wrapper

Native Android wrapper for [Haver Digital](https://haver-digital.vercel.app) — a Hebrew AI companion for elderly Israelis.

## Build

```powershell
cd C:\haver-android
.\setup.ps1          # debug APK (default)
.\setup.ps1 -Release # release APK (still debug-signed for sideloading)
```

The script auto-downloads the Gradle wrapper if needed. Requires Java 17+ (bundled with Android Studio).

APK output: `app\build\outputs\apk\debug\app-debug.apk`

## Install

```
adb install -r app\build\outputs\apk\debug\app-debug.apk
```

## Kiosk Setup (Full Lock-Down)

The app uses Android **Screen Pinning** by default (no setup needed).  
For **full Device Owner kiosk** (no status bar, no nav buttons):

```bash
# Factory-reset the tablet first, then run before any Google account is added:
adb shell dpm set-device-owner ai.osinet.haver/.HaverDeviceAdminReceiver
```

Then relaunch the app — it will auto-enter full kiosk mode.

**Exit kiosk:** Press Back → enter PIN `1234`

## Features

| Feature | Implementation |
|---|---|
| Fullscreen WebView | `startLockTask()` + immersive mode |
| Microphone fix | `WebChromeClient.onPermissionRequest` auto-grants — native Android handles audio, no echo loop |
| Camera | Same auto-grant |
| Screen always on | `FLAG_KEEP_SCREEN_ON` |
| Auto-start on boot | `BootReceiver` |
| PIN exit (1234) | `showKioskExitDialog()` |
| Home replacement | `CATEGORY_HOME` intent filter |

## Package

- **Package:** `ai.osinet.haver`
- **Min SDK:** Android 8.0 (API 26)
- **Target SDK:** Android 14 (API 34)
