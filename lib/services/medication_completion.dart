import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/medication_action.dart';
import '../models/medication_model.dart';
import 'schedule_time.dart';

/// A Once schedule is completed by its durable Taken event, including an event
/// waiting in the existing SQLite outbox. Daily/weekly courses stay active.
List<Medication> projectMedicationCompletion(
  List<Medication> medications,
  Iterable<MedicationAction> actions,
) {
  final taken = <(String, String), List<int>>{};
  for (final action in actions.where((action) => action.action == 'taken')) {
    taken
        .putIfAbsent((action.patientId, action.medicationId), () => [])
        .add(action.timestamp);
  }
  return medications.map((medication) {
    if (!medication.isOnce) return medication.withCompletion(null);
    final start = DateTime.tryParse(medication.startDate ?? '');
    final startsAt = start == null
        ? null
        : ScheduleTime.onDate('00:00', start)?.millisecondsSinceEpoch;
    int? completedAt;
    for (final timestamp
        in taken[(medication.patientId, medication.id)] ?? <int>[]) {
      if (startsAt != null && timestamp < startsAt) continue;
      if (completedAt == null || timestamp < completedAt) {
        completedAt = timestamp;
      }
    }
    return medication.withCompletion(completedAt);
  }).toList();
}

/// Serialize confirmations from different screens until their durable local
/// write finishes. A second Once confirmation can then see the first event.
class MedicationActionSerialQueue {
  final _pending = <String, Future<void>>{};

  Future<void> run(
    String patientId,
    String medicationId,
    Future<void> Function() save,
  ) {
    final key = '$patientId\u0000$medicationId';
    final previous = _pending[key] ?? Future<void>.value();
    final operation = previous.catchError((Object _) {}).then((_) => save());
    _pending[key] = operation;
    return operation.whenComplete(() {
      if (identical(_pending[key], operation)) _pending.remove(key);
    });
  }
}

/// Joins schedules with history without adding a completion collection/column.
/// The history subscription changes only when the set of patients changes.
Stream<List<Medication>> medicationCompletionStream({
  required Stream<List<Medication>> schedules,
  required Stream<List<MedicationAction>> Function(List<String> patientIds)
  actionsForPatients,
}) {
  late final StreamController<List<Medication>> controller;
  StreamSubscription<List<Medication>>? scheduleSub;
  StreamSubscription<List<MedicationAction>>? actionSub;
  List<Medication> medications = const [];
  List<MedicationAction> actions = const [];
  String? patientKey;
  var historyReady = false;
  var cancelled = false;
  var generation = 0;
  var schedulesDone = false;
  var actionsDone = false;

  void emit() {
    if (!cancelled && historyReady) {
      controller.add(projectMedicationCompletion(medications, actions));
    }
  }

  void closeIfDone() {
    if (!cancelled && schedulesDone && actionsDone) controller.close();
  }

  controller = StreamController<List<Medication>>(
    onListen: () {
      scheduleSub = schedules.listen(
        (rows) {
          medications = rows;
          final ids = rows.map((row) => row.patientId).toSet().toList()..sort();
          final key = ids.join('\u0000');
          if (key == patientKey) {
            emit();
            return;
          }
          patientKey = key;
          final currentGeneration = ++generation;
          unawaited(actionSub?.cancel());
          actions = const [];
          historyReady = ids.isEmpty;
          actionsDone = ids.isEmpty;
          if (ids.isEmpty) {
            emit();
            return;
          }
          actionSub = actionsForPatients(ids).listen(
            (history) {
              if (cancelled || generation != currentGeneration) return;
              actions = history;
              historyReady = true;
              emit();
            },
            onError: (Object error, StackTrace stack) {
              if (cancelled || generation != currentGeneration) return;
              // A history connection failure must not hide usable schedules.
              // Patient history normally falls back to its durable SQLite cache.
              debugPrint(
                'Medication completion history deferred (${error.runtimeType}).',
              );
              historyReady = true;
              emit();
            },
            onDone: () {
              if (generation != currentGeneration) return;
              actionsDone = true;
              closeIfDone();
            },
          );
        },
        onError: controller.addError,
        onDone: () {
          schedulesDone = true;
          closeIfDone();
        },
      );
    },
    onPause: () {
      scheduleSub?.pause();
      actionSub?.pause();
    },
    onResume: () {
      scheduleSub?.resume();
      actionSub?.resume();
    },
    onCancel: () async {
      cancelled = true;
      generation++;
      await scheduleSub?.cancel();
      await actionSub?.cancel();
    },
  );
  return controller.stream;
}
