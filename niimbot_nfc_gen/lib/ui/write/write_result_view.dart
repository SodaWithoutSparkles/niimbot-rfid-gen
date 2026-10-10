// What the write did: a summary, a per-page grid, and the warnings verbatim.

import 'package:flutter/material.dart';

import '../../core/nfc/write_runner.dart';

class WriteResultView extends StatelessWidget {
  final WriteReport report;

  const WriteResultView({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              report.isSuccess ? 'Written' : 'Write failed',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${report.writtenCount} written · '
              '${report.failedCount} failed · '
              '${report.mismatchedCount} mismatched',
              style: theme.textTheme.bodyMedium,
            ),
            if (report.fatalError != null) ...[
              const SizedBox(height: 12),
              Text(
                report.fatalError!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 16),

            if (report.outcomes.isNotEmpty) ...[
              Text('Pages', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final outcome in report.outcomes)
                    _OutcomeChip(outcome: outcome),
                ],
              ),
              const SizedBox(height: 16),
            ],

            if (report.warnings.isNotEmpty) ...[
              Text('Warnings', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              for (final warning in report.warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('⚠ ', style: TextStyle(color: scheme.error)),
                      Expanded(
                        child: Text(warning, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OutcomeChip extends StatelessWidget {
  final PageOutcome outcome;

  const _OutcomeChip({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, colour, tooltip) = switch (outcome.status) {
      PageStatus.written => ('✓', scheme.primary, 'written and verified'),
      PageStatus.mismatched => ('⚠', scheme.error, 'written but not confirmed'),
      PageStatus.failed => ('✗', scheme.error, 'rejected by the tag'),
      PageStatus.notWritten => ('–', scheme.outline, 'not attempted'),
    };

    return Tooltip(
      message: 'page ${outcome.page}: $tooltip',
      child: Container(
        width: 46,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colour),
        ),
        child: Column(
          children: [
            Text(icon, style: TextStyle(color: colour, fontSize: 14)),
            Text(
              '${outcome.page}',
              style: TextStyle(color: colour, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}