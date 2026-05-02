# FlashGuard — Final Setup Guide

## Files in this package

| File | Purpose |
|------|---------|
| `pubspec.yaml` | All Flutter/Dart dependencies |
| `lib/main.dart` | Complete app — background service + UI |
| `android/app/src/main/AndroidManifest.xml` | Full manifest with all permissions |
| `android/app/src/main/res/xml/file_paths.xml` | FileProvider paths for camera plugin |

---

## Step 1 — Create your Flutter project

```bash
flutter create flashguard
cd flashguard
```

Then **replace** the generated files with the ones in this package.

---

## Step 2 — Add google-services.json

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Open project **flashguard-99c20**
3. Go to **Project Settings → Your apps → Android app**
4. Download **google-services.json**
5. Place it at `android/app/google-services.json`

---

## Step 3 — Update android/app/build.gradle

Open `android/app/build.gradle` and make sure these values are set:

```gradle
android {
    defaultConfig {
        applicationId "com.flashguard.app"   // must match AndroidManifest package
        minSdkVersion 23                      // minimum — REQUIRED
        targetSdkVersion 34
        compileSdkVersion 34
        versionCode 1
        versionName "2.0.0"
    }
}

// Add at the very bottom of the file:
apply plugin: 'com.google.gms.google-services'
```

---

## Step 4 — Update android/build.gradle (project-level)

Open `android/build.gradle` and add inside `dependencies {}`:

```gradle
dependencies {
    classpath 'com.android.tools.build:gradle:8.1.0'
    classpath 'com.google.gms:google-services:4.4.1'   // ADD THIS LINE
}
```

---

## Step 5 — Run pub get

```bash
flutter pub get
```

---

## Step 6 — Enable Special Permissions on the test device

These two permissions **cannot** be granted via code — the user must enable them manually:

| Permission | Where to enable |
|------------|----------------|
| Usage Access | Settings → Apps → Special app access → Usage access → FlashGuard → ON |
| Notification Access | Settings → Apps → Special app access → Notification access → FlashGuard → ON |

The app opens the correct settings screen on first launch.

---

## Step 7 — Run the app

```bash
flutter run
```

---

## Firebase Realtime Database structure

After the app runs, data will appear at these paths:

```
devices/
  <device-id>/
    meta/
      online: true
      startedAt: <timestamp>
    location/
      lat, lng, accuracy, speed, address, timestamp
    captures/
      <push-id>/
        url, timestamp, camera
    notifications/
      <push-id>/
        package, title, body, timestamp
    appUsage/
      updatedAt: <timestamp>
      data/
        <package_name>/
          name, seconds
    commands/
      capture: false    ← set to true from your parent dashboard to trigger camera
```

---

## Firebase Realtime Database Rules (paste in Firebase Console)

```json
{
  "rules": {
    "devices": {
      "$deviceId": {
        ".read": "auth != null",
        ".write": "auth != null"
      }
    }
  }
}
```
