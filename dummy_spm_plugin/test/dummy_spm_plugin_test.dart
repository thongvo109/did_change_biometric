import 'package:flutter_test/flutter_test.dart';
import 'package:dummy_spm_plugin/dummy_spm_plugin.dart';
import 'package:dummy_spm_plugin/dummy_spm_plugin_platform_interface.dart';
import 'package:dummy_spm_plugin/dummy_spm_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDummySpmPluginPlatform
    with MockPlatformInterfaceMixin
    implements DummySpmPluginPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final DummySpmPluginPlatform initialPlatform = DummySpmPluginPlatform.instance;

  test('$MethodChannelDummySpmPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDummySpmPlugin>());
  });

  test('getPlatformVersion', () async {
    DummySpmPlugin dummySpmPlugin = DummySpmPlugin();
    MockDummySpmPluginPlatform fakePlatform = MockDummySpmPluginPlatform();
    DummySpmPluginPlatform.instance = fakePlatform;

    expect(await dummySpmPlugin.getPlatformVersion(), '42');
  });
}
