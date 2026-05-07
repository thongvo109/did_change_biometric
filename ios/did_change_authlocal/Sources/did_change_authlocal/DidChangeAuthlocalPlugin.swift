import Flutter
import UIKit
import LocalAuthentication

/// A Flutter plugin that detects biometric enrollment changes on iOS using
/// two complementary mechanisms:
///
/// ## 1. MethodChannel (One-shot check)
/// - `get_token`: Returns the current biometric domain state as a base64 token.
/// - `acknowledge_change`: No-op on iOS (token comparison handles this naturally).
///
/// ## 2. EventChannel (Real-time monitoring stream)
/// - `did_change_authlocal/events`: A reactive stream that monitors biometric
///   changes by observing app lifecycle transitions via `NotificationCenter`.
///
/// ### How monitoring works:
/// iOS does not broadcast biometric enrollment changes directly. Instead,
/// this plugin uses `LAContext.evaluatedPolicyDomainState` which returns a
/// `Data` blob representing the current biometric enrollment state. When the
/// user adds/removes Face ID or Touch ID, this blob changes.
///
/// The plugin monitors `willEnterForeground` notifications to re-check the
/// biometric state whenever the user returns from Settings. This is the most
/// reliable approach since users modify biometrics via:
///   Settings → Face ID & Passcode → Set Up Face ID / Reset Face ID
///
/// The stream emits status strings consistent with the Android side:
/// - `"biometric_valid"`: No change detected
/// - `"biometric_did_change"`: Biometric enrollment has changed
/// - `"biometric_invalid"`: Biometric not available on this device
///
/// Uses `distinctUntilChanged`-style filtering on the native side so Dart
/// only receives events when the actual status changes.
public class DidChangeAuthlocalPlugin: NSObject, FlutterPlugin {

    // ═══════════════════════════════════════════════════════════════════
    // Properties
    // ═══════════════════════════════════════════════════════════════════

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?

    /// The stream handler that manages biometric monitoring lifecycle
    private var streamHandler: BiometricStreamHandler?

    // ═══════════════════════════════════════════════════════════════════
    // Plugin Registration
    // ═══════════════════════════════════════════════════════════════════

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = DidChangeAuthlocalPlugin()

        // MethodChannel — one-shot API
        let methodChannel = FlutterMethodChannel(
            name: "did_change_authlocal",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        instance.methodChannel = methodChannel

        // EventChannel — real-time monitoring stream
        let streamHandler = BiometricStreamHandler()
        let eventChannel = FlutterEventChannel(
            name: "did_change_authlocal/events",
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(streamHandler)
        instance.eventChannel = eventChannel
        instance.streamHandler = streamHandler

        // Register for application delegate callbacks (optional cleanup)
        registrar.addApplicationDelegate(instance)
    }

    // ═══════════════════════════════════════════════════════════════════
    // MethodChannel Handler
    // ═══════════════════════════════════════════════════════════════════

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "get_token":
            getBiometricToken(result: result)
        case "check":
            checkBiometric(result: result)
        case "acknowledge_change":
            // On iOS, acknowledgment is a no-op since token comparison
            // naturally handles repeated checks. We update the stream's
            // last known token so it doesn't re-emit "changed".
            streamHandler?.acknowledgeCurrentState()
            result("acknowledged")
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    // One-shot biometric check (MethodChannel)
    // ═══════════════════════════════════════════════════════════════════

    /// Retrieves the current biometric domain state as a base64 token.
    ///
    /// This token changes whenever biometric data (Face ID or Touch ID) is
    /// added or removed on the device.
    private func getBiometricToken(result: @escaping FlutterResult) {
        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &authError
        ) else {
            let code = authError?.code ?? -1
            result(
                FlutterError(
                    code: "biometric_invalid",
                    message: "Biometric authentication not available: \(authError?.localizedDescription ?? "Unknown error")",
                    details: "Error code: \(code)"
                )
            )
            return
        }

        guard let biometricData = context.evaluatedPolicyDomainState else {
            result(
                FlutterError(
                    code: "biometric_invalid",
                    message: "Could not retrieve biometric domain state",
                    details: nil
                )
            )
            return
        }

        let token = biometricData.base64EncodedString()
        result(token)
    }

    /// Checks biometric status and returns a status string matching Android format.
    ///
    /// This provides a consistent API between iOS and Android for the
    /// MethodChannel "check" call. On iOS, it checks against the last known
    /// token stored in the stream handler.
    private func checkBiometric(result: @escaping FlutterResult) {
        guard let currentToken = getCurrentBiometricToken() else {
            result(
                FlutterError(
                    code: "biometric_invalid",
                    message: "Biometric not available",
                    details: nil
                )
            )
            return
        }

        if let handler = streamHandler, handler.hasTokenChanged(currentToken) {
            result(
                FlutterError(
                    code: "biometric_did_change",
                    message: "Biometric data has changed (Face ID or Touch ID).",
                    details: nil
                )
            )
        } else {
            result("biometric_valid")
        }
    }

    /// Helper to get current biometric token, or nil if unavailable.
    private func getCurrentBiometricToken() -> String? {
        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &authError
        ) else {
            return nil
        }

        guard let biometricData = context.evaluatedPolicyDomainState else {
            return nil
        }

        return biometricData.base64EncodedString()
    }
}

// ═══════════════════════════════════════════════════════════════════════
// BiometricStreamHandler — FlutterStreamHandler implementation
// ═══════════════════════════════════════════════════════════════════════

/// Manages the EventChannel stream for real-time biometric monitoring.
///
/// When Dart calls `listen()`, this handler:
/// 1. Captures the current biometric token as a baseline
/// 2. Observes `willEnterForegroundNotification` from `NotificationCenter`
/// 3. On each foreground transition, re-checks the token and emits status
///    if it changed
///
/// When Dart calls `cancel()`, the handler removes all observers to conserve
/// resources.
///
/// This architecture mirrors the Android side which uses:
/// - `DefaultLifecycleObserver.onResume` → equivalent to `willEnterForeground`
/// - Periodic polling → not needed on iOS since token comparison is instant
///   and reliable (no KeyStore race conditions)
private class BiometricStreamHandler: NSObject, FlutterStreamHandler {

    /// EventSink for sending events to Dart
    private var eventSink: FlutterEventSink?

    /// Last known biometric token — used for change detection
    private var lastKnownToken: String?

    /// Last emitted status — used for distinctUntilChanged filtering
    private var lastEmittedStatus: String?

    /// Notification observer token for cleanup
    private var foregroundObserver: NSObjectProtocol?

    // ─────────────────────────────────────────────────────────────────
    // FlutterStreamHandler protocol
    // ─────────────────────────────────────────────────────────────────

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events

        // Capture baseline token
        lastKnownToken = getCurrentToken()

        // Emit initial status
        let initialStatus = lastKnownToken != nil ? "biometric_valid" : "biometric_invalid"
        emitIfChanged(initialStatus)

        // Observe app foreground transitions via NotificationCenter
        // This fires when user returns from Settings → Face ID & Passcode
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onAppWillEnterForeground()
        }

        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        // Remove notification observer
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }

        eventSink = nil
        lastEmittedStatus = nil

        return nil
    }

    // ─────────────────────────────────────────────────────────────────
    // Lifecycle handling
    // ─────────────────────────────────────────────────────────────────

    /// Called when the app returns to the foreground.
    ///
    /// This is the primary detection mechanism on iOS. When the user:
    /// 1. Goes to Settings → Face ID & Passcode
    /// 2. Adds/removes a face or fingerprint
    /// 3. Returns to the app
    ///
    /// The `evaluatedPolicyDomainState` token will have changed.
    private func onAppWillEnterForeground() {
        guard eventSink != nil else { return }

        let currentToken = getCurrentToken()

        guard let currentToken = currentToken else {
            // Biometric became unavailable (e.g., all faces/fingerprints removed)
            if lastKnownToken != nil {
                // Do not clear lastKnownToken here to keep the state bound
                emitIfChanged("biometric_did_change")
            } else {
                emitIfChanged("biometric_invalid")
            }
            return
        }

        if let lastToken = lastKnownToken {
            if currentToken != lastToken {
                // Token changed — biometric enrollment was modified
                // We intentionally DO NOT update lastKnownToken here.
                // It remains "bound" in the changed state until the developer
                // explicitly calls acknowledgeChange(). This mirrors Android's
                // KeyPermanentlyInvalidatedException behavior.
                emitIfChanged("biometric_did_change")
            } else {
                // No change
                emitIfChanged("biometric_valid")
            }
        } else {
            // First time having a token (biometric was just set up)
            lastKnownToken = currentToken
            emitIfChanged("biometric_did_change")
        }
    }

    // ─────────────────────────────────────────────────────────────────
    // Public methods (called from plugin)
    // ─────────────────────────────────────────────────────────────────

    /// Updates the baseline token to the current state.
    /// Called when the developer acknowledges a biometric change.
    func acknowledgeCurrentState() {
        lastKnownToken = getCurrentToken()
        emitIfChanged("biometric_valid")
    }

    /// Checks if the given token differs from the last known token.
    func hasTokenChanged(_ currentToken: String) -> Bool {
        guard let lastToken = lastKnownToken else {
            return true // No baseline — consider it changed
        }
        return currentToken != lastToken
    }

    // ─────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────

    /// Gets the current biometric domain state token.
    ///
    /// Returns `nil` if biometric is not available or not configured.
    private func getCurrentToken() -> String? {
        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &authError
        ) else {
            return nil
        }

        guard let biometricData = context.evaluatedPolicyDomainState else {
            return nil
        }

        return biometricData.base64EncodedString()
    }

    /// Emits a status to Dart only if it differs from the last emitted status.
    ///
    /// This implements `distinctUntilChanged` behavior on the native side,
    /// so Dart doesn't receive duplicate events (e.g., "valid" → "valid").
    private func emitIfChanged(_ status: String) {
        guard status != lastEmittedStatus else { return }
        lastEmittedStatus = status
        eventSink?(status)
    }
}
