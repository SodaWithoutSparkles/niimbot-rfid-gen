// buildWritePlan against the real golden image.

import 'dart:typed_data';

import 'package:niimbot_nfc_gen/core/generator.dart';
import 'package:niimbot_nfc_gen/core/nfc/write_plan.dart';
import 'package:test/test.dart';

/// The golden image from generator_test.dart, NTAG213.
const goldenHex =
    '1de1a1d59310108013c00000e11012000103a00c742fc763e017dbf935a3fd09be86168ff5de9eff112aac55452558e8848403e8eabebae8bb22ebc960a540537fcccad380063526fc53bc2694803b743a8b6488741abe5d162ff80ed7e61e8f66e35d5d3e24e38a6a56550e6d152f2a21a4ebe3db4b279be1d8d6832b4f1f29d68fba0b5d339b383e3487110000000000000000000000000000000000000000000000bd000000ff000000001234567855550000';

Uint8List goldenImage() => hexToBytes(goldenHex);

/// A real image for [type], straight out of the generator.
Future<Uint8List> imageFor(TagType type) async =>
    (await generateTagFile(GenerateInput(
      mediaType: 1,
      widthMm: 50,
      heightMm: 30,
      gapMm: 6,
      nominalQuantity: 230,
      uid: '1D:E1:A1:93:10:10:80',
      tagType: type,
    )))
        .bytes;

PagePlan planFor(List<PagePlan> plan, int page) =>
    plan.firstWhere((p) => p.page == page);

void main() {
  group('NTAG213, the layout in plan.md section 2', () {
    late List<PagePlan> plan;
    final memory = goldenImage();

    setUpAll(() => plan = buildWritePlan(memory, TagType.ntag213));

    test('is 34 pages: 5..34 full, then 41..44', () {
      expect(plan.length, 34);
      expect(plan.map((p) => p.page).toList(), [
        ...List.generate(30, (i) => 5 + i), // 5..34
        41,
        42,
        43,
        44,
      ]);
    });

    test('pages 5..34 are full pages', () {
      for (var page = 5; page <= 34; page++) {
        expect(planFor(plan, page).isFull, isTrue, reason: 'page $page');
      }
    });

    test('the payload pages carry the image verbatim', () {
      for (var page = 5; page <= 34; page++) {
        expect(planFor(plan, page).value,
            memory.sublist(page * 4, page * 4 + 4).toList(),
            reason: 'page $page');
      }
    });

    test('page 41 is the config page, mask C0 00 00 FF', () {
      final entry = planFor(plan, 41);
      expect(entry.mask, [0xc0, 0x00, 0x00, 0xff]);
      expect(entry.isFull, isFalse);
      expect(entry.value, memory.sublist(41 * 4, 41 * 4 + 4).toList());
    });

    test('page 42 is the password page, mask 9F 00 00 00', () {
      final entry = planFor(plan, 42);
      expect(entry.mask, [0x9f, 0x00, 0x00, 0x00]);
      expect(entry.isFull, isFalse);
    });

    test('page 43 is the password bytes, a full page', () {
      final entry = planFor(plan, 43);
      expect(entry.mask, [0xff, 0xff, 0xff, 0xff]);
      expect(entry.isFull, isTrue);
      expect(entry.value, [0x12, 0x34, 0x56, 0x78]);
    });

    test('page 44 is the pack bytes, partial', () {
      final entry = planFor(plan, 44);
      expect(entry.mask, [0xff, 0xff, 0x00, 0x00]);
      expect(entry.isFull, isFalse);
      expect(entry.value.sublist(0, 2), [0x55, 0x55]);
    });

    test('never plans the UID header or the NDEF capability container', () {
      // Bytes 0..19 belong to the UID/BCC and CC. The write mask is zero there.
      expect(plan.any((p) => p.page < 5), isFalse);
      expect(plan.map((p) => p.page), isNot(contains(41 - 1)));
    });

    test('never plans the pages between the payload and the config area', () {
      expect(plan.map((p) => p.page), isNot(contains(35)));
      expect(plan.map((p) => p.page), isNot(contains(40)));
    });
  });

  group('NTAG215 and NTAG216 use the same mask at a different place', () {
    test('NTAG215 moves the four config pages to 131..134', () async {
      final memory = await imageFor(TagType.ntag215);
      expect(memory.length, 540);
      final plan = buildWritePlan(memory, TagType.ntag215);

      expect(plan.length, 34);
      expect(plan.map((p) => p.page).toList().sublist(30), [131, 132, 133, 134]);
      expect(planFor(plan, 131).mask, [0xc0, 0x00, 0x00, 0xff]);
      expect(planFor(plan, 132).mask, [0x9f, 0x00, 0x00, 0x00]);
      expect(planFor(plan, 133).isFull, isTrue);
      expect(planFor(plan, 134).mask, [0xff, 0xff, 0x00, 0x00]);
    });

    test('NTAG216 moves them to 227..230', () async {
      final memory = await imageFor(TagType.ntag216);
      expect(memory.length, 924);
      final plan = buildWritePlan(memory, TagType.ntag216);

      expect(plan.length, 34);
      expect(plan.map((p) => p.page).toList().sublist(30), [227, 228, 229, 230]);
      expect(planFor(plan, 227).mask, [0xc0, 0x00, 0x00, 0xff]);
      expect(planFor(plan, 228).mask, [0x9f, 0x00, 0x00, 0x00]);
      expect(planFor(plan, 229).isFull, isTrue);
      expect(planFor(plan, 230).mask, [0xff, 0xff, 0x00, 0x00]);
    });

    test('the payload pages carry the same bytes on every tag type', () async {
      final thirteen = buildWritePlan(goldenImage(), TagType.ntag213);
      final fifteen = buildWritePlan(await imageFor(TagType.ntag215), TagType.ntag215);

      for (var page = 5; page <= 34; page++) {
        expect(planFor(fifteen, page).value, planFor(thirteen, page).value);
      }
    });
  });

  group('apply is a read-modify-write', () {
    test('a full page ignores what is on the tag', () {
      const entry = PagePlan(page: 5, mask: [0xff, 0xff, 0xff, 0xff], value: [1, 2, 3, 4]);
      expect(entry.isFull, isTrue);
      expect(entry.apply([0xaa, 0xbb, 0xcc, 0xdd]), [1, 2, 3, 4]);
    });

    test('a partial page keeps the bytes outside the mask', () {
      // Byte 0: mask C0 takes the high two bits of 0xA5 (0x80) and keeps the
      // low two bits of what is already on the tag (0xFF & ~0xC0 = 0x3F).
      const entry = PagePlan(
        page: 41,
        mask: [0xc0, 0x00, 0x00, 0xff],
        value: [0xa5, 0x11, 0x22, 0x33],
      );
      expect(entry.apply([0xff, 0x5a, 0x6b, 0x7c]), [0xbf, 0x5a, 0x6b, 0x33]);
    });

    test('a partial mask only takes the bits it owns', () {
      // 0x9F takes the high nibble of 0xA0 (0x80) and the low three bits of
      // what is on the tag (0x5C & 0x60 = 0x40). The bit 0x9F does not cover
      // is the low one, so it stays whatever the tag had: 0x5C & ~0x9F = 0x40.
      const entry = PagePlan(
        page: 42,
        mask: [0x9f, 0, 0, 0],
        value: [0xa0, 0, 0, 0],
      );
      expect(entry.apply([0x5c, 0, 0, 0]), [0xc0, 0, 0, 0]);
    });

    test('a page with no mask bytes of ours is returned untouched', () {
      const entry = PagePlan(page: 9, mask: [0, 0, 0, 0], value: [1, 2, 3, 4]);
      expect(entry.apply([9, 8, 7, 6]), [9, 8, 7, 6]);
    });

    test('the result never exceeds a byte', () {
      const entry = PagePlan(
        page: 41,
        mask: [0xc0, 0, 0, 0xff],
        value: [0xff, 0, 0, 0xff],
      );
      final applied = entry.apply([0xff, 0xff, 0xff, 0xff]);
      expect(applied.every((b) => b >= 0 && b <= 0xff), isTrue);
      expect(applied, [0xff, 0xff, 0xff, 0xff]);
    });
  });

  test('a memory image too small for the plan skips what does not fit', () {
    // NTAG213 mapping reaches byte 177. A 176-byte image cannot hold it.
    final plan = buildWritePlan(Uint8List(176)..setRange(0, 176, goldenImage()), TagType.ntag213);
    expect(plan.any((p) => p.page == 44), isFalse);
    expect(plan.map((p) => p.page), isNot(contains(44)));
    expect(planFor(plan, 43).isFull, isTrue);
  });
}