
import 'dummy_spm_plugin_platform_interface.dart';

class DummySpmPlugin {
  Future<String?> getPlatformVersion() {
    return DummySpmPluginPlatform.instance.getPlatformVersion();
  }
}
