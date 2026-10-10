// Roll details card: preset picker, custom fields, live validation.

import 'package:flutter/material.dart';

import '../../core/generator.dart';
import 'write_controller.dart';

class RollForm extends StatelessWidget {
  final WriteController controller;

  const RollForm({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Roll details', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),

            DropdownButtonFormField<int>(
              // The roll profile label is long, and without isExpanded the
              // selected item overflows instead of ellipsising.
              isExpanded: true,
              initialValue: controller.presetIndex,
              decoration: const InputDecoration(
                labelText: 'Preset',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var i = 0; i < controller.presets.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      controller.presets[i].label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) controller.selectPreset(value);
              },
            ),

            // Custom editing is only offered in Custom mode, but the preset
            // picker stays enabled so there is always a way back out.
            if (controller.isCustom) ...[
              const SizedBox(height: 12),
              Text('Custom', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: controller.mediaType,
                decoration: const InputDecoration(
                  labelText: 'Media type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final option in mediaTypes)
                    DropdownMenuItem(
                      value: option.value,
                      child: Text(option.label),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) controller.setMediaType(value);
                },
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: controller,
                key_: 'widthMm',
                label: 'Width (mm)',
                value: controller.widthMm,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: controller,
                key_: 'heightMm',
                label: 'Length (mm)',
                value: controller.heightMm,
                // Continuous media has neither, and the generator zeroes them.
                enabled: !controller.isContinuous,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: controller,
                key_: 'gapMm',
                label: 'Gap (mm)',
                value: controller.gapMm,
                enabled: !controller.isContinuous,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: controller,
                key_: 'nominalQuantity',
                label: 'Nominal quantity',
                value: controller.nominalQuantity,
              ),
            ],

            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(
                  label: 'usage limit ${controller.safeUsageLimit()}',
                ),
                _Chip(label: rollProfile.id),
                _Chip(
                  label: controller.isCustom ? 'custom' : 'catalogue',
                ),
                if (controller.noCatalogueBarcode)
                  const _Chip(
                    label: 'no catalogue barcode for these dimensions',
                    warn: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final WriteController controller;
  final String key_;
  final String label;
  final int value;
  final bool enabled;

  const _NumberField({
    required this.controller,
    required this.key_,
    required this.label,
    required this.value,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      // Re-key on the preset so switching preset reloads the value, while
      // typing in Custom mode keeps the cursor where the user left it.
      key: ValueKey('${controller.presetIndex}-$key_'),
      initialValue: value < 0 ? '' : '$value',
      enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        errorText: controller.errorFor(key_),
      ),
      onChanged: (text) => controller.setField(key_, text),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool warn;

  const _Chip({required this.label, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      backgroundColor: warn
          ? scheme.errorContainer
          : scheme.surfaceContainerHighest,
      labelStyle: TextStyle(
        fontSize: 12,
        color: warn ? scheme.onErrorContainer : scheme.onSurfaceVariant,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}