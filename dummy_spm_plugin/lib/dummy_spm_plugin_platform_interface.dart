import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'dummy_spm_plugin_method_channel.dart';

abstract class DummySpmPluginPlatform extends PlatformInterface {
  /// Constructs a DummySpmPluginPlatform.
  DummySpmPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static DummySpmPluginPlatform _instance = MethodChannelDummySpmPlugin();

  /// The default instance of [DummySpmPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelDummySpmPlugin].
  static DummySpmPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DummySpmPluginPlatform] when
  /// they register themselves.
  static set instance(DummySpmPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
