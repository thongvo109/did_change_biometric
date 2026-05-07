import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'dummy_plugin_method_channel.dart';

abstract class DummyPluginPlatform extends PlatformInterface {
  /// Constructs a DummyPluginPlatform.
  DummyPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static DummyPluginPlatform _instance = MethodChannelDummyPlugin();

  /// The default instance of [DummyPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelDummyPlugin].
  static DummyPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DummyPluginPlatform] when
  /// they register themselves.
  static set instance(DummyPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
