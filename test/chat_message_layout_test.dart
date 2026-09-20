import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/models/chat_message.dart';
import 'package:medicare/widgets/chat_message_layout.dart';

void main() {
  ChatMessage message({String? url, String text = ''}) => ChatMessage(
    id: 'm',
    senderId: 'p',
    senderName: 'Patient',
    text: text,
    createdAt: 1,
    type: 'sos_location',
    mapUrl: url,
  );
  test('map links survive serialization and legacy blank fields', () {
    const url = 'https://maps.google.com/?q=1.3,103.8';
    final original = message(url: url);
    expect(
      ChatMessage.fromMap('m', original.toMap()).locationUri.toString(),
      url,
    );
    expect(
      message(url: '', text: 'Location: $url').locationUri.toString(),
      url,
    );
    expect(
      message(
        url: 'https://www.google.com/maps/search/?api=1&query=1.3,103.8',
      ).locationUri,
      isNotNull,
    );
    expect(message(text: 'Acquiring my location').locationUri, isNull);
    expect(message(url: 'javascript:alert(1)').locationUri, isNull);
  });
  for (final mine in [true, false]) {
    testWidgets('forward is outside ${mine ? 'sent' : 'received'} bubble', (
      tester,
    ) async {
      var forwarded = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: ChatMessageLayout(
                mine: mine,
                onForward: () => forwarded = true,
                bubble: Container(
                  key: const Key('bubble'),
                  width: 240,
                  padding: const EdgeInsets.all(12),
                  child: const Text('A message'),
                ),
              ),
            ),
          ),
        ),
      );
      final bubble = tester.getRect(find.byKey(const Key('bubble')));
      final button = tester.getRect(find.byTooltip('Forward message'));
      expect(
        mine ? button.right <= bubble.left : button.left >= bubble.right,
        isTrue,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('bubble')),
          matching: find.byType(IconButton),
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Forward message'));
      expect(forwarded, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
