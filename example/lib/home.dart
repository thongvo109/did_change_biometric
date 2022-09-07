import 'package:did_change_authlocal/did_change_authlocal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomwPage extends StatefulWidget {
  const HomwPage({super.key});

  @override
  State<HomwPage> createState() => _HomwPageState();
}

class _HomwPageState extends State<HomwPage> with WidgetsBindingObserver {
  String _tokenBiometric = "";

  @override
  void initState() {
    super.initState();
    onGetTokenBiometric();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumeUpdateBiometric();
    }
  }

  //This function will compare previous and current token after the user create a new Face ID and clears Face ID

  void onResumeUpdateBiometric() async {
    await DidChangeAuthLocal.instance
        .onCheckBiometric(token: _tokenBiometric)
        .then((value) {
      if (value == BiometricStatus.changed) {
        showDialog(
            context: context,
            builder: (BuildContext context) {
              return const AlertDialog(
                title: Text('Alert'),
                content: Text('The biometric data has been changed'),
              );
            });
      }
    });
  }

  //Just only for iOS
  Future<void> onGetTokenBiometric() async {
    try {
      final platformVersion =
          await DidChangeAuthLocal.instance.getTokenBiometric();

      setState(() {
        _tokenBiometric = platformVersion;
      });
    } on PlatformException catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Did change Local Auth'),
      ),
      body: Center(child: Text(_tokenBiometric)),
    );
  }
}
