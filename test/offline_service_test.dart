import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/services/offline_service.dart';

class SaveOnDispose extends StatefulWidget {
  const SaveOnDispose({super.key, required this.write});
  final Future<void> write;
  @override
  State<SaveOnDispose> createState() => _SaveOnDisposeState();
}

class _SaveOnDisposeState extends State<SaveOnDispose> {
  @override
  void dispose() {
    unawaited(OfflineService.save(widget.write));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets(
    'offline writes during tree disposal safely update pending listeners',
    (tester) async {
      final write = Completer<void>();
      Widget screen(bool show) => MaterialApp(
        home: Column(
          children: [
            ValueListenableBuilder<int>(
              valueListenable: OfflineService.pending,
              builder: (_, n, _) => Text('Pending $n'),
            ),
            if (show) SaveOnDispose(write: write.future),
          ],
        ),
      );
      await tester.pumpWidget(screen(true));
      await tester.pumpWidget(screen(false));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(OfflineService.pending.value, 1);
      write.complete();
      await tester.pump();
      expect(OfflineService.pending.value, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'late rejected offline writes clear pending without unhandled errors',
    (tester) async {
      final write = Completer<void>();
      final save = OfflineService.save(write.future);
      await tester.pump(const Duration(seconds: 3));
      await save;
      expect(OfflineService.pending.value, 1);
      write.completeError(StateError('permission denied'));
      await tester.pump();
      expect(OfflineService.pending.value, 0);
      expect(OfflineService.error.value, contains('permission denied'));
      expect(tester.takeException(), isNull);
      OfflineService.error.value = null;
      await tester.pump();
    },
  );
}
