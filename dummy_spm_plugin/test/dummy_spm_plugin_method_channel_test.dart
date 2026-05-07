import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dummy_spm_plugin/dummy_spm_plugin_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelDummySpmPlugin platform = MethodChannelDummySpmPlugin();
  const MethodChannel channel = MethodChannel('dummy_spm_plugin');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
