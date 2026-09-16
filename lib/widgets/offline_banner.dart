import 'package:flutter/material.dart';
import '../services/offline_service.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      OfflineService.offline,
      OfflineService.pending,
      OfflineService.error,
    ]),
    builder: (_, _) {
      final error = OfflineService.error.value;
      final pending = OfflineService.pending.value;
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
                          ? 'Offline • Saved data available. $pending change(s) waiting to sync.'
                          : '$pending change(s) waiting for server confirmation.'),
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
