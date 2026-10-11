// readRoll against a fake tag, driven by the reference tag dump.

import 'dart:typed_data';

import 'package:niimbot_nfc_gen/core/generator.dart';
import 'package:niimbot_nfc_gen/core/nfc/roll_reader.dart';
import 'package:niimbot_nfc_gen/core/nfc/tag_session.dart';
import 'package:test/test.dart';

/// The dump from a tag that already prints, page for page.
Uint8List referenceImage() {
  const hex =
      '1de1a1d59310108013c00000e11012000103a00c742fc763e017dbf935a3fd09be86168ff5de9eff112aac55452558e8848403e8eabebae8bb22ebc960a540537fcccad380063526fc53bc2694803b743a8b6488741abe5d162ff80ed7e61e8f66e35d5d3e24e38a6a56550e6d152f2a21a4ebe3db4b279be1d8d6832b4f1f29d68fba0b5d339b383e3487110000000000000000000000000000000000000000000000bd000000ff000000001234567855550000';
  return hexToBytes(hex);
}

/// The physical UID: bytes 0..2 and 4..7. Byte 3 is a BCC check byte, not part
/// of the UID. This mirrors what NFCTag.id reports.
Uint8List uidOf(Uint8List image) => Uint8List.fromList([
      image[0],
      image[1],
      image[2],
      image[4],
      image[5],
      image[6],
      image[7],
    ]);

/// A tag that answers READ from a byte image, the way hardware would.
class FakeTag implements TagSession {
  final Uint8List image;
  final int? pageCount;

  @override
  final TagInfo tag;

  /// When set, every read fails.
  final bool unreadable;

  FakeTag._(this.image, this.pageCount, {this.unreadable = false})
      : tag = TagInfo(
          uid: uidOf(image),
          pageCount: pageCount,
        );

  factory FakeTag.fromImage(Uint8List image,
          {int? pageCount, bool unreadable = false}) =>
      FakeTag._(image, pageCount, unreadable: unreadable);

  final List<int> reads = [];

  @override
  Future<Uint8List> transceive(Uint8List command, {Duration? timeout}) async {
    if (command[0] != 0x30) return Uint8List(0);
    reads.add(command[1]);
    if (unreadable) {
      throw const NfcException(NfcErrorKind.comms, 'no response');
    }
    final page = command[1];
    final start = page * 4;
    if (start >= image.length) {
      throw const NfcException(NfcErrorKind.comms, 'out of range');
    }
    // Real hardware returns 16 bytes spanning four pages; past the end of
    // memory it wraps, which is why the reader keeps only the first four.
    final out = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      final at = start + i;
      out[i] = at < image.length ? image[at] : image[at % image.length];
    }
    return out;
  }

  @override
  Future<void> revive() async {}

  @override
  Future<void> close() async {}
}

void main() {
  group('readPages', () {
    test('reads 120 bytes from pages 5..34', () async {
      final tag = FakeTag.fromImage(referenceImage(), pageCount: 45);
      final payload = await readPages(tag, payloadStartPage, payloadPageCount);

      expect(payload.length, 120);
      expect(payload, referenceImage().sublist(20, 140));
    });

    test('reads every page in turn, keeping only the first four bytes',
        () async {
      final tag = FakeTag.fromImage(referenceImage(), pageCount: 45);
      await readPages(tag, payloadStartPage, payloadPageCount);

      // Regression: striding by four pages while keeping four bytes silently
      // skipped pages 6, 7 and 8.
      expect(tag.reads.length, payloadPageCount);
      expect(tag.reads.first, 5);
      expect(tag.reads.last, 34);
    });

    test('a tag that will not answer read reports it', () {
      final tag = FakeTag.fromImage(referenceImage(),
          pageCount: 45, unreadable: true);
      expect(
        () => readPages(tag, payloadStartPage, payloadPageCount),
        throwsA(isA<NfcException>()),
      );
    });
  });

  group('readRoll recognises a real roll tag', () {
    late RollInfo info;

    setUpAll(() async {
      final tag = FakeTag.fromImage(referenceImage(), pageCount: 45);
      final probe = await readRoll(tag);
      expect(probe, isA<RollFound>());
      info = (probe as RollFound).info;
    });

    test('recovers the geometry', () {
      expect(info.widthMm, 50);
      expect(info.heightMm, 30);
      expect(info.gapMm, 6);
      expect(info.geometryLabel, '50 × 30 mm, 6mm gap');
    });

    test('recovers the roll sizes', () {
      expect(info.nominalQuantity, 230);
      expect(info.usageLimit, 276);
      expect(info.capacity, 276);
      expect(info.mediaTypeLabel, 'Gap labels');
    });

    test('recovers the catalogue code and finds the entry', () {
      expect(info.barcode, '022824255');
      expect(info.catalogueEntry, isNotNull);
      expect(info.catalogueEntry!.sourceId, '80000579');
    });

    test('reports an unused roll as full', () {
      expect(info.count, 0);
      expect(info.isPrinted, isFalse);
      expect(info.rollsLeft, 230);
      expect(info.capacityLeft, 276);
    });

    test('reports the tag type from GET_VERSION', () {
      expect(info.tagType, TagType.ntag213);
      expect(info.pageCount, 45);
    });
  });

  group('readRoll rejects what is not a roll tag', () {
    test('a blank tag fails the CRC', () async {
      final tag = FakeTag.fromImage(Uint8List(180), pageCount: 45);
      final probe = await readRoll(tag);

      expect(probe, isA<RollNotRecognised>());
      expect(
        (probe as RollNotRecognised).reason,
        contains('not NIIMBOT roll data'),
      );
    });

    test('a tag that is not an NTAG21x is rejected before reading', () async {
      final tag = FakeTag.fromImage(referenceImage(), pageCount: 20);
      final probe = await readRoll(tag);

      expect(probe, isA<RollNotRecognised>());
      expect(tag.reads, isEmpty, reason: 'no point reading a wrong tag');
    });

    test('a tag with an unknown page count is rejected', () async {
      final tag = FakeTag.fromImage(referenceImage());
      expect(await readRoll(tag), isA<RollNotRecognised>());
    });

    test('an unreadable tag says so rather than crashing', () async {
      final tag = FakeTag.fromImage(referenceImage(),
          pageCount: 45, unreadable: true);
      final probe = await readRoll(tag);

      expect(probe, isA<RollNotRecognised>());
      expect((probe as RollNotRecognised).reason, contains('Could not read'));
    });

    test('a payload belonging to another UID is rejected', () async {
      // Same roll data, different physical tag.
      final image = referenceImage();
      final other = Uint8List.fromList(image);
      other[4] = 0xAB; // UID byte 3 changes, payload identity does not

      final probe = await readRoll(FakeTag.fromImage(other, pageCount: 45));
      expect(probe, isA<RollNotRecognised>());
      expect((probe as RollNotRecognised).reason, contains('different UID'));
    });
  });

  group('usage maths', () {
    test('a partly printed roll reports what is left', () async {
      final image = referenceImage();
      // Re-encode the payload with a non-zero count, as a used roll would have.
      final payload = Uint8List.fromList(image.sublist(20, 140));
      final decoded = decodePayload(payload);
      ByteData.view(
        decoded.mutable.buffer,
        decoded.mutable.offsetInBytes,
        decoded.mutable.lengthInBytes,
      ).setUint16(2, 120, Endian.little);
      image.setRange(20, 140, encodePayload(decoded.mutable, decoded.fixed));

      final probe = await readRoll(FakeTag.fromImage(image, pageCount: 45));
      final info = (probe as RollFound).info;

      expect(info.count, 120);
      expect(info.isPrinted, isTrue);
      expect(info.rollsLeft, 110);
      expect(info.capacityLeft, 156);
    });
  });
}