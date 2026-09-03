import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/medication_action.dart';
import '../../models/medication_model.dart';
import '../../models/mood_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../services/reminder_service.dart';
import '../../services/sos_hold_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/medicine_art.dart';
import '../../widgets/calendar_art.dart';
import '../../widgets/mood_art.dart';
import '../../widgets/mood_face_art.dart';
import '../../widgets/sos_countdown_overlay.dart';

class PatientHomePage extends StatefulWidget {
  const PatientHomePage({
    super.key,
    required this.user,
    required this.onOpenMood,
    this.externalSosRequestId = 0,
    this.onExternalSosRequestHandled,
  });

  final UserModel user;
  final VoidCallback onOpenMood;
  final int externalSosRequestId;
  final ValueChanged<int>? onExternalSosRequestHandled;

  @override
  State<PatientHomePage> createState() => _PatientHomePageState();
}

class _PatientHomePageState extends State<PatientHomePage>
    with WidgetsBindingObserver {
  static const _moodColors = [
    Color(0xFFF2A98D),
    Color(0xFFFFD49C),
    Color(0xFFFFF0A7),
    Color(0xFFF4B7B5),
    Color(0xFFE8D8B9),
    Color(0xFFDDE99B),
    Color(0xFFE4D6E8),
    Color(0xFFC7D8E5),
    Color(0xFFCDE4C8),
  ];

  final _firestore = FirestoreService();
  List<Medication> _meds = [];
  List<MedicationAction> _actions = [];
  DailyMood? _todayMood;
  List<Appointment> _apts = [];
  StreamSubscription<List<Medication>>? _medSub;
  StreamSubscription<List<MedicationAction>>? _actionSub;
  StreamSubscription<DailyMood?>? _moodSub;
  StreamSubscription<List<Appointment>>? _aptSub;
  late final _sosHold = SosHoldController(
    onChanged: (holding, progress) {
      if (!mounted) return;
      setState(() {
        _sosHolding = holding;
        _sosProgress = progress;
      });
    },
    onComplete: _startSosCountdown,
  );
  bool _sosHolding = false;
  double _sosProgress = 0;
  bool _sosCountdownVisible = false;
  int _handledExternalSosRequestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _medSub = _firestore.getMedicationsByPatient(widget.user.uid).listen((
      meds,
    ) {
      if (mounted) setState(() => _meds = meds);
    }, onError: (_) {});
    _actionSub = _firestore
        .getMedicationActionsByPatient(widget.user.uid)
        .listen((actions) {
          if (mounted) setState(() => _actions = actions);
        }, onError: (_) {});
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    _moodSub = _firestore.getTodayMood(widget.user.uid, todayStr).listen((
      mood,
    ) {
      if (mounted) setState(() => _todayMood = mood);
    }, onError: (_) {});
    _aptSub = _firestore.getAppointmentsByPatient(widget.user.uid).listen((
      apts,
    ) {
      if (mounted) setState(() => _apts = apts);
      _handleTappedNotification();
    }, onError: (_) {});
    _queueExternalSosIfNeeded();
    NotificationService.instance.tapNotifier.addListener(_handleTappedNotification);
    _handleTappedNotification();
  }

  @override
  void didUpdateWidget(covariant PatientHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalSosRequestId != widget.externalSosRequestId) {
      _queueExternalSosIfNeeded();
    }
  }

  void _queueExternalSosIfNeeded() {
    final requestId = widget.externalSosRequestId;
    if (requestId <= 0 || requestId == _handledExternalSosRequestId) return;
    _handledExternalSosRequestId = requestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startSosCountdown(triggerSource: 'home_widget');
      widget.onExternalSosRequestHandled?.call(requestId);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancelSosHold();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.instance.tapNotifier
        .removeListener(_handleTappedNotification);
    _sosHold.dispose();
    _medSub?.cancel();
    _actionSub?.cancel();
    _moodSub?.cancel();
    _aptSub?.cancel();
    super.dispose();
  }

  void _handleTappedNotification() {
    final payload = NotificationService.instance.tapNotifier.value;
    if (payload == null) return;
    if (payload.startsWith('appointment:')) {
      final aptId = payload.substring('appointment:'.length);
      _markAppointmentCompleted(aptId);
    }
  }

  Future<void> _markAppointmentCompleted(String aptId) async {
    final target = _apts.where((apt) => apt.id == aptId).toList();
    if (target.isEmpty) return;
    final apt = target.first;
    if (apt.status == 'completed') return;
    await _firestore.updateAppointmentStatus(aptId, 'completed');
  }

  MedicationAction? _todayActionForMed(String medId) {
    final todayMs = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ).millisecondsSinceEpoch;
    for (final action in _actions) {
      if (action.medicationId == medId && action.timestamp >= todayMs) {
        return action;
      }
    }
    return null;
  }

  List<Widget> _buildAppointments() {
    final now = DateTime.now();
    final upcoming = <Appointment>[];
    for (final apt in _apts) {
      if (apt.status == 'completed') continue;
      final aptDateTime = _parseAppointmentDateTime(apt);
      if (aptDateTime == null || !aptDateTime.isBefore(now)) {
        upcoming.add(apt);
      }
    }
    upcoming.sort((a, b) {
      final ad = _parseAppointmentDateTime(a) ?? DateTime(9999);
      final bd = _parseAppointmentDateTime(b) ?? DateTime(9999);
      return ad.compareTo(bd);
    });
    final next = upcoming.isNotEmpty ? [upcoming.first] : <Appointment>[];
    return [
      const Text(
        'Appointments',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w900,
          color: AppTheme.navy,
        ),
      ),
      const SizedBox(height: 10),
      if (next.isEmpty)
        const Text(
          'No appointment...',
          style: TextStyle(color: AppTheme.muted, fontSize: 13),
        )
      else
        ...next.map((apt) => _AppointmentCard(apt: apt)),
    ];
  }

  DateTime? _parseAppointmentDateTime(Appointment apt) {
    final normalizedDate = apt.date.replaceAll('/', '-');
    final normalizedTime = apt.time;
    return DateTime.tryParse('${normalizedDate}T$normalizedTime');
  }

  void _startSosHold() {
    if (_sosCountdownVisible) return;
    _sosHold.start();
  }

  void _cancelSosHold() {
    _sosHold.cancel();
  }

  void _startSosCountdown({String triggerSource = 'in_app'}) {
    if (_sosCountdownVisible) return;
    _sosCountdownVisible = true;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x00000000),
      transitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          SosCountdownOverlay(
            durationSeconds: 5,
            onComplete: () {
              Navigator.of(dialogContext).pop();
              _sosCountdownVisible = false;
              _sendSos(triggerSource: triggerSource);
            },
            onCancel: () {
              Navigator.of(dialogContext).pop();
              _sosCountdownVisible = false;
            },
          ),
    ).whenComplete(() => _sosCountdownVisible = false);
  }

  Future<void> _sendSos({String triggerSource = 'in_app'}) async {
    try {
      await _firestore.triggerSos(widget.user, triggerSource: triggerSource);
      if (mounted) {
        debugPrint(
          'SOS sent: patient=${widget.user.uid} '
          'caregiver=${widget.user.caregiverId ?? '(none)'}',
        );
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            icon: const Icon(
              Icons.check_circle,
              color: Color(0xFFE85B61),
              size: 40,
            ),
            title: const Text('SOS Submitted'),
            content: const Text(
              'Your SOS was submitted. Delivery to your caregiver and family '
              'depends on their connection and notification settings.',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE85B61),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('SOS send failed: $e');
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            icon: const Icon(Icons.error, color: Colors.red, size: 40),
            title: const Text('Send Failed'),
            content: const Text(
              'Could not send SOS. Please try again.',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayMeds = _meds.where((m) => m.isScheduledForDate(today)).toList()
      ..sort(Medication.compareByTime);

    Medication? nextMed;
    for (final med in todayMeds) {
      final action = _todayActionForMed(med.id);
      if (action != null &&
          (action.action == 'taken' || action.action == 'skipped')) {
        continue;
      }
      nextMed = med;
      break;
    }

    final List<Medication> sameTimeMeds = [];
    if (nextMed != null) {
      for (final med in todayMeds) {
        final action = _todayActionForMed(med.id);
        if (action != null &&
            (action.action == 'taken' || action.action == 'skipped')) {
          continue;
        }
        if (med.time24h == nextMed.time24h) {
          sameTimeMeds.add(med);
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Schedule",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          if (_meds.isEmpty && _actions.isEmpty)
            const _HomeCard(child: Center(child: CircularProgressIndicator()))
          else if (todayMeds.isEmpty)
            const _HomeCard(
              child: Text(
                'No medications scheduled today.',
                style: TextStyle(fontSize: 13),
              ),
            )
          else if (nextMed == null)
            _HomeCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF48AF75),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'All medications taken for today!',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ...sameTimeMeds.map(
              (med) => Padding(
                padding: EdgeInsets.only(
                  bottom: med == sameTimeMeds.last ? 0 : 10,
                ),
                child: _MedicationCard(
                  medication: med,
                  todayAction: _todayActionForMed(med.id),
                  firestore: _firestore,
                  userUid: widget.user.uid,
                ),
              ),
            ),
          const SizedBox(height: 12),
          ..._buildAppointments(),
          const SizedBox(height: 12),
          _HomeCard(
            child: _todayMood != null
                ? Row(
                    children: [
                      MoodFaceArt(
                        size: 42,
                        moodIndex: _todayMood!.moodIndex,
                        color: _moodColors[_todayMood!.moodIndex],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Daily Mood',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Feeling ${_todayMood!.moodLabel}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            const SizedBox(height: 9),
                            Row(
                              children: [
                                const Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Checked in for today',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.muted,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: widget.onOpenMood,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.navy,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Change',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                FilledButton(
                                  onPressed: () async {
                                    final today = DateTime.now();
                                    final dateStr =
                                        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
                                    await _firestore.deleteMood(
                                      patientId: widget.user.uid,
                                      date: dateStr,
                                    );
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.navy,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Back',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const MoodArt(size: 42),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Daily Mood',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              'How do you feel today?',
                              style: TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 9),
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      MoodFaceArt(
                                        size: 28,
                                        moodIndex: 2,
                                        color: _moodColors[2],
                                      ),
                                      const SizedBox(width: 5),
                                      MoodFaceArt(
                                        size: 28,
                                        moodIndex: 3,
                                        color: _moodColors[3],
                                      ),
                                      const SizedBox(width: 5),
                                      MoodFaceArt(
                                        size: 28,
                                        moodIndex: 5,
                                        color: _moodColors[5],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: widget.onOpenMood,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.navy,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Start Check-in',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4F4),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFFC8BEBE)),
            ),
            child: Column(
              children: [
                Container(
                  width: 170,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFB71C1C)),
                  ),
                  child: const Text(
                    'Emergency Support',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 14),
                Listener(
                  key: const Key('sos-button'),
                  onPointerDown: (_) => _startSosHold(),
                  onPointerUp: (_) => _cancelSosHold(),
                  onPointerCancel: (_) => _cancelSosHold(),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFE0E0),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFFFC6C6),
                          blurRadius: 0,
                          spreadRadius: 7,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE94141),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: _sosHolding
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  value: _sosProgress,
                                  strokeWidth: 3,
                                  color: Colors.white,
                                  backgroundColor: Color(0x66FFFFFF),
                                ),
                              )
                            : const Text(
                                'SOS',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Press & Hold for 2 seconds',
                  style: TextStyle(fontSize: 10, color: Color(0xFF555555)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFBFC2C5)),
      ),
      child: child,
    );
  }
}

class _MedicationCard extends StatefulWidget {
  const _MedicationCard({
    required this.medication,
    required this.firestore,
    required this.userUid,
    this.todayAction,
  });

  final Medication medication;
  final FirestoreService firestore;
  final String userUid;
  final MedicationAction? todayAction;

  @override
  State<_MedicationCard> createState() => _MedicationCardState();
}

class _MedicationCardState extends State<_MedicationCard> {
  bool _processing = false;

  bool get _taken => widget.todayAction?.action == 'taken';
  bool get _skipped => widget.todayAction?.action == 'skipped';
  bool get _snoozed => widget.todayAction?.action == 'snoozed';

  Future<void> _take() async {
    if (_processing) return;
    setState(() => _processing = true);
    final med = widget.medication;
    ReminderService().clearSnooze(med.id);
    await widget.firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      patientId: widget.userUid,
      action: 'taken',
    );
    if (med.currentStock > 0) {
      await widget.firestore.updateMedicationStock(
        med.id,
        med.currentStock - 1,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Medicine marked as taken')));
    }
  }

  Future<void> _skip() async {
    if (_processing) return;
    setState(() => _processing = true);
    final med = widget.medication;
    ReminderService().clearSnooze(med.id);
    await widget.firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      patientId: widget.userUid,
      action: 'skipped',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medicine marked as skipped')),
      );
    }
  }

  Future<void> _snooze() async {
    if (_processing) return;
    setState(() => _processing = true);
    final snoozedUntil = DateTime.now().millisecondsSinceEpoch + 10 * 60 * 1000;
    final med = widget.medication;
    ReminderService().snoozeMedication(med.id, snoozedUntil);
    await widget.firestore.logMedicationAction(
      medicationId: med.id,
      medicationName: med.name,
      patientId: widget.userUid,
      action: 'snoozed',
      snoozedUntil: snoozedUntil,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder snoozed for 10 minutes')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.medication;
    final scheduled = med.scheduledDateTime;
    final timeReady = scheduled == null || !DateTime.now().isBefore(scheduled);
    final buttonsEnabled = !_processing && !_taken && !_skipped && timeReady;
    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Next Medicine',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: med.imageUrl != null
                    ? Image.network(
                        med.imageUrl!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: 56,
                          height: 56,
                          child: MedicineArt(size: 56),
                        ),
                      )
                    : const SizedBox(
                        width: 56,
                        height: 56,
                        child: MedicineArt(size: 56),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med.time,
                      style: const TextStyle(
                        color: AppTheme.navy,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      med.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(med.dosage, style: const TextStyle(fontSize: 10)),
                    Text(
                      'Stock: ${med.currentStock}',
                      style: TextStyle(
                        fontSize: 11,
                        color: med.currentStock <= 5
                            ? Colors.red
                            : AppTheme.muted,
                        fontWeight: med.currentStock <= 5
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          if (_taken || _skipped)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color:
                    (_taken ? const Color(0xFF48AF75) : const Color(0xFFE85B61))
                        .withValues(alpha: .12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _taken ? Icons.check_circle : Icons.cancel,
                    color: _taken
                        ? const Color(0xFF48AF75)
                        : const Color(0xFFE85B61),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _taken ? 'Taken' : 'Skipped',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _taken
                          ? const Color(0xFF48AF75)
                          : const Color(0xFFE85B61),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (_snoozed)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2AE36).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.alarm, color: Color(0xFFF2AE36), size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Snoozed - will remind again soon',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF2AE36),
                      ),
                    ),
                  ],
                ),
              ),
            if (!timeReady)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.navy.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.lock_clock,
                      color: AppTheme.navy,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Available at ${med.time}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navy,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Take',
                    color: const Color(0xFF48AF75),
                    enabled: buttonsEnabled,
                    onTap: _take,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    label: 'Skip',
                    color: const Color(0xFFE85B61),
                    enabled: buttonsEnabled,
                    onTap: _skip,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    label: 'Snooze',
                    color: const Color(0xFFF2AE36),
                    enabled: buttonsEnabled,
                    onTap: _snooze,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FilledButton(
        onPressed: enabled ? onTap : null,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.4),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.apt});

  final Appointment apt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF2E72B7),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: CalendarArt(size: 40),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  apt.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${apt.date} · ${apt.time}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.navy,
                  ),
                ),
                if (apt.location.isNotEmpty)
                  Text(
                    apt.location,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
