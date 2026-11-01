import 'package:flutter/material.dart';

import '../services/incoming_call_bridge.dart';

Future<void> showIncomingCallSettings(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _IncomingCallSettings(),
);

class _IncomingCallSettings extends StatefulWidget {
  const _IncomingCallSettings();

  @override
  State<_IncomingCallSettings> createState() => _IncomingCallSettingsState();
}

class _IncomingCallSettingsState extends State<_IncomingCallSettings>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _permissions;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final permissions = await IncomingCallBridge.instance.permissions();
      if (mounted) {
        setState(() {
          _permissions = permissions;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not read Android call settings.');
      }
    }
  }

  Future<void> _open(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Open MediCare permissions in Android Settings.',
        );
      }
    }
  }

  Widget _status(String label, String permission) {
    final value = _permissions?[permission];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        value == true ? Icons.check_circle : Icons.info_outline,
        color: value == true ? Colors.green : Colors.orange,
      ),
      title: Text(label),
      subtitle: Text(
        value == true
            ? 'Allowed'
            : value == false
            ? 'Not allowed'
            : 'Checking…',
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Incoming call alerts'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Allow notifications and full-screen calls to receive the incoming '
            'call screen over the lock screen. Android may show a call banner '
            'while the phone is unlocked.',
          ),
          const SizedBox(height: 8),
          _status('Notifications', 'notifications'),
          _status('Full-screen incoming calls', 'fullScreen'),
          _status('Incoming calls channel', 'channelEnabled'),
          const Text(
            'Keep the Incoming calls channels enabled and your ringtone volume '
            'audible. Silent mode, Do Not Disturb and phone battery restrictions '
            'can limit call alerts.',
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () =>
            _open(IncomingCallBridge.instance.openNotificationSettings),
        child: const Text('Notifications'),
      ),
      TextButton(
        onPressed: () =>
            _open(IncomingCallBridge.instance.openFullScreenSettings),
        child: const Text('Full-screen calls'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
