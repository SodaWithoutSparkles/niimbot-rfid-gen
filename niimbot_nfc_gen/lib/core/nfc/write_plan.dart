// Turns the generator's flat memory image into the list of pages to write.
//
// This is the single source of truth for what the app touches on the tag, and
// it is deliberately layout-independent: the provisioning write mask decides
// which bytes are ours, the tag type decides where those bytes physically live.
// If the physical page numbering turns out to differ from what we expect, the
// write still only ever touches bytes the mask claims, and the verify pass
// reports the difference instead of corrupting anything.

import 'dart:typed_data';

import '../generator/export.dart';
import '../generator/uid_masks.dart';
import '../log.dart';

class PagePlan {
  /// Physical page index on the tag.
  final int page;

  /// Four entries. A zero byte is not ours and must not be written.
  final List<int> mask;

  /// Four entries, the bytes the generator wants at those positions.
  final List<int> value;

  const PagePlan({required this.page, required this.mask, required this.value});

  /// True when every byte of the page is ours, so no read-back is needed.
  bool get isFull => mask.every((m) => m == 0xff);

  /// Read-modify-write: keep whatever is on the tag outside the mask.
  List<int> apply(List<int> actual) => List<int>.generate(
        4,
        (i) => (actual[i] & ~mask[i]) | (value[i] & mask[i]),
      );

  /// Where the bytes that are not ours sit, for the log.
  List<int> get untouchedIndices => [
        for (var i = 0; i < 4; i++)
          if (mask[i] != 0xff) i,
      ];

  @override
  String toString() => 'PagePlan(page: $page, mask: $mask, full: $isFull)';
}

/// Groups the masked bytes of [memory] by physical page.
///
/// The mapping is the one in export.dart: offsets below 164 keep their
/// position, offsets from 164 on sit in the tag's config area.
List<PagePlan> buildWritePlan(Uint8List memory, TagType type) {
  final spec = getTagTypeSpec(type);
  final writeMask = provisioningMasks().write;

  final masks = <int, List<int>>{};
  final values = <int, List<int>>{};

  for (var offset = 0; offset < writeMask.length; offset++) {
    final maskByte = writeMask[offset];
    if (maskByte == 0) continue;

    final target = offset < 164 ? offset : spec.configPage * 4 + offset - 164;
    if (target >= memory.length) {
      // Defensive only: the plan and the mask are generated together, so this
      // cannot happen for a matching tag type.
      log.w('write plan: offset $offset maps to byte $target, past the '
          '${memory.length}-byte image; skipped');
      continue;
    }

    final page = target ~/ 4;
    final byteInPage = target % 4;
    (masks[page] ??= List<int>.filled(4, 0))[byteInPage] = maskByte;
    (values[page] ??= List<int>.filled(4, 0))[byteInPage] = memory[target];
  }

  final pages = masks.keys.toList()..sort();
  final plan = [
    for (final page in pages)
      PagePlan(page: page, mask: masks[page]!, value: values[page]!),
  ];

  debugLog(() => 'buildWritePlan($type): ${plan.length} pages '
      '${plan.map((p) => p.page).join(',')}');
  return plan;
}