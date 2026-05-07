import 'dart:async';

import 'package:did_change_authlocal/did_change_authlocal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Did Change Biometric',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _tokenBiometric = '';
  AuthLocalStatus? _lastStatus;
  final List<String> _streamEvents = [];

  /// Stream subscription for real-time biometric monitoring
  StreamSubscription<AuthLocalStatus>? _biometricSubscription;

  @override
  void initState() {
    super.initState();
    _loadToken();
    _startMonitoring();
  }

  @override
  void dispose() {
    // IMPORTANT: Cancel stream subscription to stop native polling
    _biometricSubscription?.cancel();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // Stream API example (recommended for production)
  // ═══════════════════════════════════════════════════════════════════

  /// Starts listening to the biometric change stream.
  ///
  /// On Android, this uses Kotlin Coroutines Flow + lifecycle observation.
  /// The stream automatically re-checks when the user returns from Settings
  /// and polls periodically as a fallback.
  void _startMonitoring() {
    _biometricSubscription =
        DidChangeAuthLocal.instance.onBiometricChanged.listen(
      (status) async {
        setState(() {
          _lastStatus = status;
          _streamEvents.add(
            '[${DateTime.now().toIso8601String().substring(11, 19)}] '
            '${status.name}',
          );
          // Keep only the last 20 events
          if (_streamEvents.length > 20) {
            _streamEvents.removeAt(0);
          }
        });

        if (status == AuthLocalStatus.changed) {
          // Show alert when biometric change is detected via stream
          if (mounted) {
            await _showChangeAlert();
          }
        }
      },
      onError: (Object error) {
        debugPrint('Biometric stream error: $error');
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // One-shot API example (for manual checks)
  // ═══════════════════════════════════════════════════════════════════

  /// Manual one-shot biometric check (original API).
  Future<void> _manualCheck() async {
    final status = await DidChangeAuthLocal.instance.onCheckBiometric(
      token: _tokenBiometric,
    );

    setState(() => _lastStatus = status);

    if (status == AuthLocalStatus.changed && mounted) {
      await _showChangeAlert();
    }
  }

  /// Shows an alert dialog when biometric change is detected.
  Future<void> _showChangeAlert() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('⚠️ Biometric Changed'),
          content: const Text(
            'Your biometric data (fingerprint or face) has been changed. '
            'For security, please re-authenticate.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    // Acknowledge the change AFTER user has seen the alert
    await DidChangeAuthLocal.instance.acknowledgeChange();

    // Refresh the iOS token after acknowledgment
    await _loadToken();
  }

  /// Retrieves the biometric token (used for iOS comparison).
  Future<void> _loadToken() async {
    try {
      final tokenBiometric =
          await DidChangeAuthLocal.instance.getTokenBiometric();
      setState(() => _tokenBiometric = tokenBiometric);
    } on PlatformException catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (_lastStatus) {
      AuthLocalStatus.valid => Colors.green,
      AuthLocalStatus.changed => Colors.red,
      AuthLocalStatus.invalid => Colors.orange,
      null => Colors.grey,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Did Change Biometric'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            Card(
              color: statusColor.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(
                      _lastStatus == AuthLocalStatus.valid
                          ? Icons.fingerprint
                          : _lastStatus == AuthLocalStatus.changed
                              ? Icons.warning_amber_rounded
                              : Icons.fingerprint,
                      size: 48,
                      color: statusColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status: ${_lastStatus?.name.toUpperCase() ?? "MONITORING..."}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Manual check button
            FilledButton.icon(
              onPressed: _manualCheck,
              icon: const Icon(Icons.refresh),
              label: const Text('Manual Check'),
            ),
            const SizedBox(height: 16),

            // Stream events log
            Text(
              'Stream Events (live):',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _streamEvents.isEmpty
                    ? const Center(
                        child: Text(
                          'Waiting for events...\n\n'
                          'Try going to Settings → Security →\n'
                          'Fingerprint and add/remove one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: _streamEvents.length,
                        itemBuilder: (context, index) {
                          final event = _streamEvents[
                              _streamEvents.length - 1 - index];
                          final isChanged = event.contains('changed');
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              event,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color:
                                    isChanged ? Colors.red : Colors.green,
                                fontWeight: isChanged
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
