
import 'dummy_plugin_platform_interface.dart';

class DummyPlugin {
  Future<String?> getPlatformVersion() {
    return DummyPluginPlatform.instance.getPlatformVersion();
  }
}
