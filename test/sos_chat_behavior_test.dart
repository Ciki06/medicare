import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:medicare/models/chat_message.dart';
import 'package:medicare/models/sos_alert.dart';
import 'package:medicare/models/sos_response.dart';
import 'package:medicare/services/sos_access.dart';

void main() {
  test(
    'SOS response timestamps use server time and still read legacy records',
    () {
      final date = DateTime.utc(2026, 9, 15, 10);
      for (final value in [
        Timestamp.fromDate(date),
        date.millisecondsSinceEpoch,
      ]) {
        final response = SosResponse.fromMap('reply', {'createdAt': value});
        expect(response.createdAt.toUtc(), date);
        expect(
          response.isCurrentAt(date.add(const Duration(minutes: 5))),
          isFalse,
        );
      }
    },
  );
  test('SOS responses expire at five minutes, including after reopening', () {
    final created = DateTime(2026, 9, 15, 10);
    final response = SosResponse(
      id: 'reply',
      alertId: 'sos',
      senderId: 'caregiver',
      senderName: 'Carer',
      senderRole: 'caregiver',
      message: "I'm on the way",
      createdAt: created,
    );
    expect(
      response.isCurrentAt(
        created.add(const Duration(minutes: 4, seconds: 59)),
      ),
      isTrue,
    );
    expect(
      response.isCurrentAt(created.add(const Duration(minutes: 5))),
      isFalse,
    );
  });
  test('old, stopped and unrelated SOS cannot open for another account', () {
    final now = DateTime(2026, 9, 15, 10);
    SosAlert alert(String status, DateTime created) => SosAlert(
      id: 'sos',
      patientId: 'patient',
      patientName: 'Patient',
      caregiverId: 'caregiver',
      alertUserIds: ['caregiver', 'family'],
      status: status,
      createdAt: created,
    );
    expect(canReceiveSos(alert('active', now), 'family', now), isTrue);
    expect(canReceiveSos(alert('active', now), 'pharmacy', now), isFalse);
    expect(canReceiveSos(alert('active', now), 'patient', now), isFalse);
    expect(
      canReceiveSos(alert('acknowledged', now), 'caregiver', now),
      isFalse,
    );
    expect(canReceiveSos(alert('stopped', now), 'caregiver', now), isFalse);
    expect(
      canReceiveSos(
        alert('active', now.subtract(const Duration(minutes: 6))),
        'caregiver',
        now,
      ),
      isFalse,
    );
  });
  test('images show only captions and voice metadata survives forwarding', () {
    ChatMessage message(Map<String, dynamic> fields) =>
        ChatMessage.fromMap('message', fields);
    expect(message({'type': 'image', 'text': 'Image'}).displayText, isEmpty);
    expect(
      message({
        'type': 'image',
        'text': 'Image',
        'caption': 'Image',
      }).displayText,
      'Image',
    );
    expect(
      message({'type': 'image', 'caption': 'After lunch'}).displayText,
      'After lunch',
    );
    final voice = message({
      'type': 'voice',
      'text': 'Voice message',
      'durationSeconds': 12,
      'forwarded': true,
    });
    expect(voice.displayText, isEmpty);
    final copy = ChatMessage.fromMap('copy', voice.toMap());
    expect(copy.durationSeconds, 12);
    expect(copy.forwarded, isTrue);
  });
}
