import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// Emphasizes the captured address without changing the saved text or GPS pin.
class SosLocationMessage extends StatelessWidget {
  const SosLocationMessage({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final text = message.text.replaceAll(
      RegExp(r'https://maps\.google\.com/\?q=[\d.,-]+'),
      'Location shared — open map',
    );
    final range = _addressRange(text);
    return SelectableText.rich(
      range == null
          ? TextSpan(text: text)
          : TextSpan(
              children: [
                TextSpan(text: text.substring(0, range.start)),
                TextSpan(
                  text: text.substring(range.start, range.end),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: text.substring(range.end)),
              ],
            ),
    );
  }

  ({int start, int end})? _addressRange(String text) {
    if (message.locationStatus != null &&
        message.locationStatus != 'available') {
      return null;
    }
    final address = message.locationName?.trim() ?? '';
    if (address.isNotEmpty) {
      final start = text.indexOf(address);
      if (start >= 0) return (start: start, end: start + address.length);
    }

    // Older SOS messages may contain an address only in their labelled text.
    final label = RegExp(
      r'\b(?:Nearby address(?:\s*\(approx\.\))?|My location|Location address):[ \t]*',
      caseSensitive: false,
    ).firstMatch(text);
    if (label == null) return null;
    final remaining = text.substring(label.end);
    final end =
        RegExp(
          r'[\r\n]|\s+(?:Accuracy:|Captured:|This is a snapshot|https?://)',
          caseSensitive: false,
        ).firstMatch(remaining)?.start ??
        remaining.length;
    final candidate = remaining.substring(0, end).trimRight();
    if (candidate.isEmpty ||
        RegExp(
          r'^[+-]?\d+(?:\.\d+)?\s*,\s*[+-]?\d+(?:\.\d+)?\.?$',
        ).hasMatch(candidate)) {
      return null;
    }
    return (start: label.end, end: label.end + candidate.length);
  }
}
