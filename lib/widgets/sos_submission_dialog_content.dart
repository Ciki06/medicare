import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/location_coordinates.dart';

/// Shows the SOS submission result while the location lookup finishes.
/// Keeps the submitted dialog concise while GPS capture finishes separately.
class SosSubmissionDialogContent extends StatelessWidget {
  const SosSubmissionDialogContent({super.key, required this.location});

  final ValueListenable<Map<String, dynamic>?> location;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<Map<String, dynamic>?>(
    valueListenable: location,
    /// Update the message when location capture reports a new result.
    builder: (_, capture, _) {
      final available =
          capture?['locationStatus'] == 'available' &&
          LocationCoordinates.fromValues(
                capture?['latitude'],
                capture?['longitude'],
              ) !=
              null;
      final status = available
          ? 'Captured'
          : switch (capture?['locationStatus']) {
              null || 'pending' => 'Finding your location…',
              'services_disabled' => 'Device location is off',
              'permission_denied' => 'MediCare needs location permission',
              _ => 'Current position unavailable',
            };
      return Text(
        'Your SOS alert will be sent to your linked caregiver and family members.'
        '\n\nLocation: $status',
        textAlign: TextAlign.left,
      );
    },
  );
}
