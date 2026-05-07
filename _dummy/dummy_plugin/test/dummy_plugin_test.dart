import 'package:flutter_test/flutter_test.dart';
import 'package:dummy_plugin/dummy_plugin.dart';
import 'package:dummy_plugin/dummy_plugin_platform_interface.dart';
import 'package:dummy_plugin/dummy_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockDummyPluginPlatform
    with MockPlatformInterfaceMixin
    implements DummyPluginPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final DummyPluginPlatform initialPlatform = DummyPluginPlatform.instance;

  test('$MethodChannelDummyPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelDummyPlugin>());
  });

  test('getPlatformVersion', () async {
    DummyPlugin dummyPlugin = DummyPlugin();
    MockDummyPluginPlatform fakePlatform = MockDummyPluginPlatform();
    DummyPluginPlatform.instance = fakePlatform;

    expect(await dummyPlugin.getPlatformVersion(), '42');
  });
}
