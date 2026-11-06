import 'package:flutter/material.dart';

import '../models/medication_model.dart';

/// Shared read-only presentation for completed appointments.
class CompletedAppointmentCard extends StatelessWidget {
  const CompletedAppointmentCard({
    super.key,
    required this.appointment,
    this.patientName,
  });

  final Appointment appointment;
  final String? patientName;

  @override
  Widget build(BuildContext context) {
    const completedColor = Color(0xFF2E8B57);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: completedColor, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: completedColor.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: completedColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appointment.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                Text(
                  '${patientName ?? appointment.patientName} - ${appointment.date} ${appointment.displayTime}',
                  style: const TextStyle(fontSize: 10, color: Colors.black),
                ),
                if (appointment.location.isNotEmpty)
                  Text(
                    appointment.location,
                    style: const TextStyle(fontSize: 10, color: Colors.black),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
