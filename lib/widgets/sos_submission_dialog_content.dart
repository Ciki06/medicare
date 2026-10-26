import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/location_coordinates.dart';

/// Keeps the submitted dialog concise while GPS capture finishes separately.
class SosSubmissionDialogContent extends StatelessWidget {
  const SosSubmissionDialogContent({super.key, required this.location});

  final ValueListenable<Map<String, dynamic>?> location;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<Map<String, dynamic>?>(
    valueListenable: location,
    builder: (_, capture, _) {
      final available =
          capture?['locationStatus'] == 'available' &&
          LocationCoordinates.fromValues(
                capture?['latitude'],
                capture?['longitude'],
              ) !=
              null;
      return Text(
        'Your SOS alert will be sent to your linked caregiver and family members.'
        '\n\nLocation: ${available ? 'On' : 'Off'}',
        textAlign: TextAlign.left,
      );
    },
  );
}
