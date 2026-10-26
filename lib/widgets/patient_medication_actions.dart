import 'package:flutter/material.dart';

/// Preserves the original three-button medication row. Patient text sizing is
/// supplied by the surrounding accessibility scope without changing geometry.
class PatientMedicationActions extends StatelessWidget {
  const PatientMedicationActions({
    super.key,
    required this.onTake,
    required this.onSkip,
    required this.onSnooze,
    this.enabled = true,
    this.spacing = 8,
  });

  final VoidCallback onTake, onSkip, onSnooze;
  final bool enabled;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w700);
    return Row(
      children: [
        for (final (index, action) in [
          ('Take', const Color(0xFF48AF75), onTake),
          ('Skip', const Color(0xFFE85B61), onSkip),
          ('Snooze', const Color(0xFFF2AE36), onSnooze),
        ].indexed) ...[
          if (index != 0) SizedBox(width: spacing),
          Expanded(
            child: SizedBox(
              height: 32,
              child: FilledButton(
                onPressed: enabled ? action.$3 : null,
                style: FilledButton.styleFrom(
                  backgroundColor: action.$2,
                  disabledBackgroundColor: action.$2.withValues(alpha: .4),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(action.$1, maxLines: 1, style: style),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
