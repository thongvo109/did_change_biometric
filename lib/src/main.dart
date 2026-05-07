import 'dart:async';
import 'dart:io';

import 'package:did_change_authlocal/src/status_enum.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A Flutter plugin to detect biometric data changes on iOS and Android.
///
/// This plugin helps protect against unauthorized biometric enrollment by
/// detecting when the user adds or removes a fingerprint/face on the device.
///
/// ## Two APIs:
///
/// ### 1. One-shot check
/// ```dart
/// final status = await DidChangeAuthLocal.instance.onCheckBiometric(
///   token: savedToken, // required for iOS, ignored on Android
/// );
/// ```
///
/// ### 2. Real-time monitoring (Stream) ⭐ Recommended
/// ```dart
/// DidChangeAuthLocal.instance.onBiometricChanged.listen((status) {
///   if (status == AuthLocalStatus.changed) {
///     // Biometric was modified! Handle it immediately.
///   }
/// });
/// ```
///
/// ## Platform architecture:
///
/// Both iOS and Android use **native EventChannel** streams with lifecycle
/// observation. No Dart-side polling or WidgetsBindingObserver needed — the
/// native side handles everything:
///
/// | | Android | iOS |
/// |---|---------|-----|
/// | Mechanism | KeyStore invalidation | LAContext domain state token |
/// | Lifecycle | DefaultLifecycleObserver | NotificationCenter willEnterForeground |
/// | Fallback | Periodic polling (5s) | Not needed (token check is instant) |
/// | Filtering | StateFlow distinctUntilChanged | Native distinctUntilChanged |
///
/// **Android**: Supports both fingerprint AND face recognition changes.
///
/// **iOS**: Supports both Face ID AND Touch ID changes.
class DidChangeAuthLocal {
  DidChangeAuthLocal._internal();

  static final DidChangeAuthLocal _instance = DidChangeAuthLocal._internal();

  /// Singleton instance of [DidChangeAuthLocal].
  static DidChangeAuthLocal get instance => _instance;

  /// The method channel used for one-shot communication with native code.
  @visibleForTesting
  final methodChannel = const MethodChannel('did_change_authlocal');

  /// The event channel used for streaming biometric status changes.
  ///
  /// Both iOS and Android native sides implement `FlutterStreamHandler`
  /// to push biometric status events through this channel.
  @visibleForTesting
  final eventChannel = const EventChannel('did_change_authlocal/events');

  /// Cached stream to avoid creating multiple subscriptions.
  Stream<AuthLocalStatus>? _biometricStream;

  // ═══════════════════════════════════════════════════════════════════
  // Stream API — Real-time monitoring
  // ═══════════════════════════════════════════════════════════════════

  /// A broadcast stream that emits [AuthLocalStatus] whenever the biometric
  /// enrollment state changes on the device.
  ///
  /// ## How it works:
  /// Both iOS and Android implement the stream natively:
  ///
  /// - **Android**: Uses `DefaultLifecycleObserver.onResume` + periodic polling
  ///   via Kotlin Coroutines Flow. Detects changes via KeyStore key invalidation.
  ///
  /// - **iOS**: Uses `NotificationCenter.willEnterForegroundNotification` to
  ///   detect when user returns from Settings. Compares `evaluatedPolicyDomainState`
  ///   tokens.
  ///
  /// Both platforms filter duplicates natively — Dart only receives events
  /// when the actual status changes.
  ///
  /// ## Usage:
  /// ```dart
  /// late StreamSubscription<AuthLocalStatus> _subscription;
  ///
  /// @override
  /// void initState() {
  ///   super.initState();
  ///   _subscription = DidChangeAuthLocal.instance.onBiometricChanged.listen(
  ///     (status) {
  ///       if (status == AuthLocalStatus.changed) {
  ///         handleBiometricChange();
  ///       }
  ///     },
  ///   );
  /// }
  ///
  /// @override
  /// void dispose() {
  ///   _subscription.cancel(); // Stops native monitoring
  ///   super.dispose();
  /// }
  /// ```
  ///
  /// **Important**: Cancel the subscription in `dispose()` to stop native
  /// monitoring and free resources.
  Stream<AuthLocalStatus> get onBiometricChanged {
    _biometricStream ??= _createBiometricStream();
    return _biometricStream!;
  }

  /// Creates the biometric monitoring stream backed by native EventChannel.
  ///
  /// Both iOS and Android emit the same status strings:
  /// - `"biometric_valid"` → [AuthLocalStatus.valid]
  /// - `"biometric_did_change"` → [AuthLocalStatus.changed]
  /// - `"biometric_invalid"` → [AuthLocalStatus.invalid]
  Stream<AuthLocalStatus> _createBiometricStream() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const Stream.empty();
    }

    return eventChannel
        .receiveBroadcastStream()
        .map((event) => _mapNativeStatus(event as String))
        .handleError((Object error) {
      if (error is PlatformException) {
        debugPrint('DidChangeAuthLocal: Stream error - ${error.message}');
      }
    });
  }

  /// Maps native status strings to [AuthLocalStatus].
  ///
  /// Both iOS and Android use the same status string format.
  AuthLocalStatus _mapNativeStatus(String status) {
    return switch (status) {
      'biometric_valid' => AuthLocalStatus.valid,
      'biometric_did_change' => AuthLocalStatus.changed,
      _ => AuthLocalStatus.invalid,
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  // One-shot API
  // ═══════════════════════════════════════════════════════════════════

  /// Checks if the biometric data has changed on the current device.
  ///
  /// On **iOS**, pass the previously saved [token] to compare against the
  /// current biometric state. Use [getTokenBiometric] to obtain the token.
  ///
  /// On **Android**, the check is done via the Android KeyStore mechanism.
  /// The [token] parameter is ignored on Android.
  ///
  /// **Tip**: For most use cases, prefer [onBiometricChanged] stream instead.
  /// The stream provides real-time monitoring without manual lifecycle handling.
  ///
  /// Returns an [AuthLocalStatus], or `null` if an unexpected error occurs.
  Future<AuthLocalStatus?> onCheckBiometric({String? token}) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      debugPrint('DidChangeAuthLocal: Unsupported platform');
      return null;
    }

    return Platform.isIOS
        ? _checkBiometricIOS(token: token ?? '')
        : _checkBiometricAndroid();
  }

  /// Retrieves the current biometric token from the platform.
  ///
  /// This token represents the current state of enrolled biometric data.
  /// Save this token and pass it to [onCheckBiometric] on subsequent app
  /// launches to detect changes.
  ///
  /// Returns an empty string on failure.
  Future<String> getTokenBiometric() async {
    try {
      final result = await methodChannel.invokeMethod<String>('get_token');
      return result ?? '';
    } on PlatformException catch (e) {
      debugPrint('DidChangeAuthLocal: Failed to get token - ${e.message}');
      return '';
    } on MissingPluginException catch (e) {
      debugPrint('DidChangeAuthLocal: Plugin not found - ${e.message}');
      return '';
    }
  }

  /// Acknowledges that a biometric change has been fully processed.
  ///
  /// Call this after you have completed all necessary actions in response
  /// to a biometric change (e.g., clearing stored credentials, logging out).
  ///
  /// After calling this method:
  /// - [onCheckBiometric] will return [AuthLocalStatus.valid]
  /// - [onBiometricChanged] stream will emit [AuthLocalStatus.valid]
  ///
  /// Works on both iOS and Android.
  ///
  /// Returns `true` if the acknowledgment was successful.
  Future<bool> acknowledgeChange() async {
    try {
      final result =
          await methodChannel.invokeMethod<String>('acknowledge_change');
      return result == 'acknowledged';
    } on PlatformException catch (e) {
      debugPrint(
          'DidChangeAuthLocal: Failed to acknowledge change - ${e.message}');
      return false;
    } on MissingPluginException catch (e) {
      debugPrint('DidChangeAuthLocal: Plugin not found - ${e.message}');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // Private platform-specific one-shot checks
  // ═══════════════════════════════════════════════════════════════════

  /// iOS-specific biometric check using token comparison.
  Future<AuthLocalStatus?> _checkBiometricIOS({String token = ''}) async {
    try {
      final result = await methodChannel.invokeMethod<String>('get_token');
      final currentToken = result ?? '';

      if (token.isEmpty) {
        return AuthLocalStatus.invalid;
      }

      return token == currentToken
          ? AuthLocalStatus.valid
          : AuthLocalStatus.changed;
    } on PlatformException catch (e) {
      return switch (e.code) {
        'biometric_invalid' => AuthLocalStatus.invalid,
        _ => null,
      };
    }
  }

  /// Android-specific biometric check using KeyStore invalidation.
  Future<AuthLocalStatus?> _checkBiometricAndroid() async {
    try {
      final result = await methodChannel.invokeMethod<String>('check');
      return result == 'biometric_valid' ? AuthLocalStatus.valid : null;
    } on PlatformException catch (e) {
      return switch (e.code) {
        'biometric_did_change' => AuthLocalStatus.changed,
        'biometric_invalid' => AuthLocalStatus.invalid,
        _ => null,
      };
    } on MissingPluginException catch (e) {
      debugPrint('DidChangeAuthLocal: Plugin not found - ${e.message}');
      return null;
    }
  }
}
