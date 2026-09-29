# FrameMind mobile (Flutter)

Android + iOS client for FrameMind: paste a video link, get an analysis of its
style, generate and edit a 100% original script, render an AI video and save
it to the gallery.

- Flutter 3.24+ / Dart 3.5+, Material 3 (light + dark)
- Riverpod 2 (`Notifier` / `AsyncNotifier`), go_router, dio
- Firebase Auth (Google, Apple, email) + Firebase Cloud Messaging
- Hive (offline cache of history / projects / chats / script drafts as JSON),
  shared_preferences (UI settings), flutter_secure_storage (FCM token)
- video_player, gal (save to gallery), share_plus

No code generation is used: models, JSON and Hive storage are hand-written, so
`flutter pub get` is all that's needed.

## 1. Install Flutter

Install Flutter 3.24 or newer (<https://docs.flutter.dev/get-started/install>)
plus Android Studio and/or Xcode, then check with `flutter doctor`.

## 2. Generate the missing platform scaffolding

This folder contains hand-written `lib/`, `pubspec.yaml`, the Android manifest
and Gradle files, `Info.plist` and `Podfile`, but not the generated platform
boilerplate (Gradle wrapper jar, launcher icons, Xcode project, …). Create it
without touching existing files:

```bash
cd mobile
flutter create . --platforms=android,ios --org io.framemind --project-name framemind
flutter pub get
```

`flutter create` never overwrites files that already exist, so `lib/`, the
manifest, `build.gradle`, `Info.plist` and `Podfile` are kept. Three follow-ups:

1. **Duplicate Gradle scripts** - newer Flutter versions generate Kotlin-DSL
   scripts. If `android/settings.gradle.kts`, `android/build.gradle.kts` or
   `android/app/build.gradle.kts` appear next to the provided Groovy files,
   delete the `.kts` files.
2. **Duplicate MainActivity** - the template derives the package from
   `--org` + project name (`io.framemind.framemind`). The app uses
   `io.framemind.app`; delete the generated
   `android/app/src/main/kotlin/io/framemind/framemind/` folder.
3. **iOS bundle id** - open `ios/Runner.xcworkspace` in Xcode and set Runner →
   General → Bundle Identifier to `io.framemind.app`.

## 3. Configure Firebase

```bash
dart pub global activate flutterfire_cli
flutterfire configure --platforms=android,ios \
  --android-package-name=io.framemind.app --ios-bundle-id=io.framemind.app
```

This writes `android/app/google-services.json`,
`ios/Runner/GoogleService-Info.plist` and `lib/firebase_options.dart` (all
gitignored). The app calls `Firebase.initializeApp()` **without options**, so it
reads the native config files; `firebase_options.dart` is not imported. If the
files are missing, the splash screen shows a "Firebase is not configured"
error with a Retry button instead of crashing.

In the Firebase console:

1. **Authentication → Sign-in method**: enable Google, Apple and Email/Password.
2. **Google (Android)**: add your debug/release SHA-1 and SHA-256 fingerprints
   (`cd android && ./gradlew signingReport`), then re-download
   `google-services.json`.
3. **Google (iOS)**: in `ios/Runner/Info.plist` replace
   `com.googleusercontent.apps.REPLACE_WITH_REVERSED_CLIENT_ID` with the
   `REVERSED_CLIENT_ID` from `GoogleService-Info.plist`.
4. **Apple**: in Xcode → Runner → *Signing & Capabilities* add **Sign in with
   Apple**, **Push Notifications** and **Background Modes → Remote
   notifications**. Upload an APNs key to Firebase (Project settings → Cloud
   Messaging).

## 4. Run

The API base URL is a compile-time define. Defaults: `http://10.0.2.2:8080/api`
on the Android emulator (the host machine), `http://localhost:8080/api`
elsewhere.

```bash
flutter run                                                    # local backend
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8080/api   # physical device
flutter run --release --dart-define=API_BASE_URL=https://api.framemind.io/api
```

Cleartext HTTP is allowed for development (`usesCleartextTraffic` on Android,
`NSAllowsLocalNetworking` on iOS). Remove these for production builds.

Tests: `flutter test`.

## Project layout

```
lib/
  main.dart                     ProviderScope + SharedPreferences
  app.dart                      MaterialApp.router, themes, push registration
  core/
    bootstrap/                  Firebase + Hive initialisation (splash)
    config/app_config.dart      API_BASE_URL, timeouts, limits
    models/enums.dart           API enums, tolerant parsing
    network/                    Dio client, auth interceptor (401 → refresh once), ApiException
    notifications/              FCM: token registration, foreground snackbars, tap routing
    router/                     go_router config, bottom-nav shell, route paths
    storage/                    Hive JSON cache, preferences, secure storage
    theme/                      Material 3 purple/indigo theme
    utils/ widgets/             date grouping, formatters, URL detection, shared UI
  features/
    auth/        splash, login (Google / Apple on iOS / email), auth repository
    home/        URL input, paste, platform detection, analyze, recents, quota chip
    analysis/    POST /video/analyze, analysis screen
    script/      script config, editor (scenes, dialogues, regenerate, drafts)
    generation/  POST /video/generate, job polling, stage stepper
    preview/     player, download → gallery (gal), share
    history/     paginated/grouped history, search/filter, chat actions, chat routing
    projects/    projects CRUD, project detail tabs
    settings/    profile, plan & usage, theme, sign out
```

## Behaviour notes

- **Auth**: every request sends `Authorization: Bearer <Firebase ID token>`;
  on `401` the token is force-refreshed and the request retried once.
- **Errors**: RFC 7807 problem responses map to `ApiException` with friendly
  messages (`429` → daily limit / slow down, `403` → upgrade for 1080p, …).
- **Opening a chat** routes by status: Analyzed → script settings,
  ScriptReady → editor, Queued/Generating → progress, Completed → preview,
  Failed → editor with an error banner.
- **Offline**: history (first page), projects, project details and opened
  chats are cached in Hive and shown when the network is unavailable. Script
  edits are auto-saved locally (debounced) and restored if newer than the
  server copy; *Save Draft* pushes them with `PUT /script/{chatId}`.
- **Generation**: the progress screen polls `GET /video/jobs/{id}` every 4 s
  only while visible; users can leave and get an FCM push
  (`data.type = video_ready | video_failed`, `data.chatId`). Tapping it opens
  the chat.
- **Downloads** are fetched from the signed URL into the temp directory and
  saved with `gal` to the "FrameMind" album (Android: Movies/FrameMind).
