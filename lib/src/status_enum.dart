/// Represents the status of biometric authentication data.
///
/// Used to determine if the biometric data on the device has changed
/// since the last authentication check.
enum AuthLocalStatus {
  /// Biometric data matches the previously stored state.
  valid,

  /// Biometric data has changed (new face/fingerprint enrolled or removed).
  changed,

  /// Biometric data is invalid or unavailable on this device.
  invalid,
}
