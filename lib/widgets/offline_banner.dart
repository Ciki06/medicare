import 'dart:async';

import 'package:flutter/material.dart';
import '../services/caregiver_sqlite_service.dart';
import '../services/offline_service.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, this.patientUid});

  final String? patientUid;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  StreamSubscription<String>? _actionChanges;
  int _pendingActions = 0;
  int _readVersion = 0;

  @override
  void initState() {
    super.initState();
    _watchActions();
  }

  @override
  void didUpdateWidget(covariant OfflineBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientUid != widget.patientUid) _watchActions();
  }

  void _watchActions() {
    _readVersion++;
    _pendingActions = 0;
    unawaited(_actionChanges?.cancel());
    _actionChanges = null;
    final uid = widget.patientUid;
    if (uid == null) return;
    _actionChanges = CaregiverSqliteService.instance.medicationActionChanges
        .where((patientUid) => patientUid == uid)
        .listen((_) => unawaited(_refreshActions(uid)));
    unawaited(_refreshActions(uid));
  }

  Future<void> _refreshActions(String uid) async {
    if (!mounted || widget.patientUid != uid) return;
    final version = ++_readVersion;
    try {
      final actions = await CaregiverSqliteService.instance
          .getPendingMedicationActions(uid);
      if (mounted &&
          version == _readVersion &&
          _pendingActions != actions.length) {
        setState(() => _pendingActions = actions.length);
      }
    } catch (_) {
      // Keep the last known count if the local database is unavailable.
    }
  }

  @override
  void dispose() {
    unawaited(_actionChanges?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      OfflineService.offline,
      OfflineService.pending,
      OfflineService.error,
    ]),
    builder: (_, _) {
      final error = OfflineService.error.value;
      final pending = OfflineService.pending.value + _pendingActions;
      final countLabel = pending == 1 ? '1 change' : '$pending changes';
      if (!OfflineService.offline.value && pending == 0 && error == null) {
        return const SizedBox.shrink();
      }
      return Material(
        color: error == null
            ? const Color(0xFFFFF3CD)
            : const Color(0xFFFFDDDD),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error ??
                      (OfflineService.offline.value
                          ? 'Offline • Saved data available. $countLabel waiting to sync.'
                          : '$countLabel waiting for server confirmation.'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (error != null)
                IconButton(
                  onPressed: () => OfflineService.error.value = null,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
      );
    },
  );
}
