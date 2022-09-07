import 'dart:io';

import 'package:did_change_authlocal/src/status_enum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DidChangeAuthLocal {
  final methodChannel = const MethodChannel('did_change_authlocal');
  DidChangeAuthLocal._internal();

  static final DidChangeAuthLocal _instance = DidChangeAuthLocal._internal();

  static DidChangeAuthLocal get instance => _instance;

  Future<AuthLocalStatus?> onCheckBiometric({String? token}) async {
    return Platform.isIOS
        ? await checkBiometricIOS(token: token ?? '')
        : await checkBiometricAndroid();
  }

  Future<String> getTokenBiometric() async {
    try {
      final result = await methodChannel.invokeMethod('get_token');
      return result.toString();
    } catch (_) {
      return '';
    }
  }

  Future<AuthLocalStatus?> checkBiometricIOS({String token = ''}) async {
    try {
      final result = await methodChannel.invokeMethod('get_token');
      debugPrint("checkBiometricIOS Token: ${result.toString()}");
      debugPrint("checkBiometricIOS Token Saved: ${token.toString()}");
      if (token == result && token.isNotEmpty) {
        return AuthLocalStatus.valid;
      } else if (token != result && token != '') {
        return AuthLocalStatus.changed;
      } else {
        return AuthLocalStatus.invalid;
      }
    } on PlatformException catch (e) {
      switch (e.code) {
        case "biometric_invalid":
          return AuthLocalStatus.invalid;
        default:
          return null;
      }
    }
  }

  //For Android ( Only Fingerprint )
  //If user does not update Finger then Biometric Status will be AuthLocalStatus.valid
  Future<AuthLocalStatus?> checkBiometricAndroid() async {
    try {
      final result = await methodChannel.invokeMethod('check');
      return result == 'biometric_valid' ? AuthLocalStatus.valid : null;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'biometric_did_change':
          return AuthLocalStatus.changed;
        case 'biometric_invalid':
          return AuthLocalStatus.invalid;
        default:
          return null;
      }
    } on MissingPluginException catch (e) {
      debugPrint(e.message);
      return null;
    }
  }
}
