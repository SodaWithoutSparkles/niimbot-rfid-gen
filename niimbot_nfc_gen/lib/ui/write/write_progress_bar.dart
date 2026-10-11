import 'package:flutter/material.dart';

import '../../core/nfc/write_progress.dart';

/// Shows where a write has got to.
///
/// A write is roughly seventy NFC round trips, and the revive after a NAK polls
/// for the tag for up to ten seconds, so an indeterminate spinner tells the
/// user nothing about whether it is working or waiting on them.
class WriteProgressBar extends StatelessWidget {
  final WriteProgress progress;

  const WriteProgressBar({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The revive is the one phase where the user may have to do something, so
    // it gets colour that stands out from the rest.
    final blocked = progress.phase == WritePhase.reviving;
    final color = blocked ? theme.colorScheme.tertiary : theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.fraction,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                progress.message,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 4,
            color: color,
          ),
        ),
      ],
    );
  }
}