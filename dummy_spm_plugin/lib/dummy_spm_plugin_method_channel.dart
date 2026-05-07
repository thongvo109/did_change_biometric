import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dummy_spm_plugin_platform_interface.dart';

/// An implementation of [DummySpmPluginPlatform] that uses method channels.
class MethodChannelDummySpmPlugin extends DummySpmPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('dummy_spm_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
