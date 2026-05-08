## 1.0.1

- Update example Android to declarative Gradle plugins (AGP 8.7.0, Gradle 8.9)
- Replace `FlutterLifecycleAdapter` with `ProcessLifecycleOwner` (standard AndroidX API)

## 1.0.0

### Breaking Changes
- **Dart SDK**: Minimum SDK bumped to `>=3.0.0 <4.0.0` (Dart 3 with sound null safety)
- **Flutter**: Minimum Flutter version bumped to `>=3.10.0`
- **Android**: Minimum SDK bumped to API 23 (Android 6.0)
- **iOS**: Minimum deployment target bumped to iOS 12.0
- Internal platform-specific methods are now private (`_checkBiometricIOS`, `_checkBiometricAndroid`)

### New Features
- **`onBiometricChanged` stream** ⭐ — Real-time biometric monitoring via native `EventChannel` on **both** iOS and Android. No Dart-side polling or lifecycle hacks needed.
  - **Android**: Uses Kotlin Coroutines `StateFlow` + `DefaultLifecycleObserver.onResume` + periodic polling fallback (5s)
  - **iOS**: Uses `NotificationCenter.willEnterForegroundNotification` + `LAContext.evaluatedPolicyDomainState` token comparison
  - Both platforms implement `distinctUntilChanged` natively — Dart only receives events when status actually changes
- **Swift Package Manager support** (Issue #9) — Added `Package.swift` for SPM compatibility, migrating the iOS plugin to Pure Swift Architecture and resolving module conflicts.
- **Android face recognition note** (Issue #7) — Clarified that Android KeyStore invalidation natively detects Face Recognition changes **only** if the device manufacturer implements it as a Class 3 (Strong) biometric (e.g. Pixel 4).
- **Persistent AuthLocalStatus binding** (Feature Request) — The `AuthLocalStatus.changed` state now stays bound (locked) across app restarts until explicitly released by calling the new `acknowledgeChange()` API.
- **iOS `check` method** — iOS now supports the same `check` MethodChannel call as Android, enabling consistent cross-platform one-shot checks
- **iOS `BiometricStreamHandler`** — Full native `FlutterStreamHandler` implementation with lifecycle observation, baseline token tracking, and automatic cleanup

### Bug Fixes
- Fixed Android plugin running unreachable code after `result.success()` / `result.error()`
- Fixed iOS `authenticateBiometric` using deprecated `base64EncodedData()` instead of `base64EncodedString()`
- Fixed example app missing `dispose()` for `WidgetsBindingObserver` (memory leak)
- Fixed example app typo `HomwPage` → `HomePage`

### Improvements
- **Platform-agnostic Dart code**: Both iOS and Android now emit through the same `EventChannel` with identical status strings — the Dart layer is completely platform-agnostic
- **No more WidgetsBindingObserver**: All lifecycle monitoring is handled natively (Kotlin + Swift), eliminating Dart-side workarounds
- Added comprehensive dartdoc comments throughout the API
- Added `@visibleForTesting` annotation for `methodChannel` and `eventChannel`
- Used Dart 3 switch expressions instead of switch statements
- Used typed `invokeMethod<String>` calls for type safety
- Upgraded Android Kotlin from 1.6.10 → 1.9.22
- Upgraded Android Gradle Plugin from 4.1.0 → 7.4.2
- Upgraded Android compileSdk from 31 → 34
- Upgraded Android Java target from 1.8 → 17
- Added Kotlin Coroutines 1.7.3 and AndroidX Lifecycle 2.7.0 dependencies
- Added `namespace` in `build.gradle` (required by AGP 7+)
- Removed deprecated `package` attribute from `AndroidManifest.xml`
- Upgraded `flutter_lints` to v5


## 0.0.6

- Update README.md

## 0.0.5

- Update README.md

## 0.0.4

- Update README.md

## 0.0.3

- Update README.md

## 0.0.2

- Update example and refactor

## 0.0.1

- Initial release
