// Tag card: type, UID with scan, and password handling.

import 'package:flutter/material.dart';

import '../../core/generator.dart';
import '../../core/nfc/write_runner.dart';
import 'field_error_text.dart';
import 'write_controller.dart';

class TagForm extends StatelessWidget {
  final WriteController controller;

  const TagForm({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final spec = getTagTypeSpec(controller.tagType);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tag', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),

            DropdownButtonFormField<TagType>(
              isExpanded: true,
              initialValue: controller.tagType,
              decoration: const InputDecoration(
                labelText: 'Tag type',
                border: OutlineInputBorder(),
                helperText: 'Determined by GET_VERSION when you scan',
              ),
              items: [
                for (final option in tagTypes)
                  DropdownMenuItem(
                    value: option.id,
                    child: Text(option.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) controller.setTagType(value);
              },
            ),
            const SizedBox(height: 8),
            Text(spec.evidence, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),

            TextFormField(
              // Re-keyed after a scan: initialValue is read only when the field
              // state is created, so a scanned UID would never appear.
              key: ValueKey('uid-${controller.uidRevision}'),
              initialValue: controller.uid,
              decoration: InputDecoration(
                labelText: 'UID',
                hintText: '1D:E1:A1:93:10:10:80',
                border: const OutlineInputBorder(),
                error: wrapFieldError(controller.errorFor('uid')),
              ),
              onChanged: controller.setUid,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: controller.busy ? null : controller.scan,
              icon: const Icon(Icons.nfc),
              label: Text(controller.scanning ?? 'Scan tag'),
            ),
            const SizedBox(height: 16),

            TextFormField(
              // Re-keyed by the quick-pick chips: initialValue alone would
              // leave the field showing the old password.
              key: ValueKey('password-${controller.passwordRevision}'),
              initialValue: controller.passwordHex,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: 'This app cannot set a password on a tag',
                border: const OutlineInputBorder(),
                error: wrapFieldError(controller.errorFor('password')),
              ),
              onChanged: controller.setPassword,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final candidate in knownPasswordHex)
                  ActionChip(
                    label: Text(candidate),
                    onPressed: () => controller.applyPassword(candidate),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.autoTryPasswords,
              onChanged: controller.busy ? null : controller.setAutoTry,
              title: const Text('Auto-try the three known passwords'),
              subtitle: const Text(
                'Each is tried at most once per tag. NTAG21x counts failed '
                'authentications against a finite limit.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}